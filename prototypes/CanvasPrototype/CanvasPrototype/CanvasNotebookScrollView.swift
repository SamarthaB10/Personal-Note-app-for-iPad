import Combine
import SwiftUI
import UIKit

enum CanvasAppearance: String, CaseIterable {
    case light, dark
    static let defaultsKey = "PersonalNotes.appearance"
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var interfaceStyle: UIUserInterfaceStyle { self == .dark ? .dark : .light }
}

struct CanvasNotebookPage: Identifiable {
    let id: UUID
    let store: CanvasPageStore
}

struct CanvasNotebookScrollRequest: Equatable {
    let id = UUID()
    let pageID: UUID
}

/// UIKit owns pinch and pan. The page column alone is the zoom target.
struct CanvasNotebookScrollView: UIViewRepresentable {
    let pages: [CanvasNotebookPage]
    let appearance: CanvasAppearance
    let isAddingPage: Bool
    let canAddPage: Bool
    let scrollRequest: CanvasNotebookScrollRequest?
    let onVisiblePageChange: (Int) -> Void
    let onZoomChange: (Int) -> Void
    let onAddPage: () -> Void

    func makeUIView(context: Context) -> CanvasNotebookScrollHost {
        CanvasNotebookScrollHost()
    }

    func updateUIView(_ view: CanvasNotebookScrollHost, context: Context) {
        view.onVisiblePageChange = onVisiblePageChange
        view.onZoomChange = onZoomChange
        view.onAddPage = onAddPage
        view.overrideUserInterfaceStyle = appearance.interfaceStyle
        view.update(pages: pages, isAddingPage: isAddingPage,
                    canAddPage: canAddPage, request: scrollRequest)
    }

    static func dismantleUIView(_ view: CanvasNotebookScrollHost, coordinator: ()) {
        view.flushSurfaces()
    }
}

@MainActor
final class CanvasNotebookScrollHost: UIScrollView, UIScrollViewDelegate {
    var onVisiblePageChange: ((Int) -> Void)?
    var onZoomChange: ((Int) -> Void)?
    var onAddPage: (() -> Void)?
    private let column = UIView()
    private let footer = UIView()
    private let addButton = UIButton(type: .system)
    private let limitLabel = UILabel()
    private var pages: [CanvasNotebookPage] = []
    private var surfaces: [UUID: CanvasSurfaceView] = [:]
    private var observations: [UUID: AnyCancellable] = [:]
    private var lastRequestID: UUID?
    private var pendingPageID: UUID?
    private var pageWidth: CGFloat = 0
    private var lastVisibleIndex: Int?
    private var lastZoomPercent = 100
    private var isLayingOut = false
    private let pageGap: CGFloat = 24
    private let footerHeight: CGFloat = 108

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = UIColor(white: 0.10, alpha: 1)
        contentInsetAdjustmentBehavior = .never
        minimumZoomScale = 0.25
        maximumZoomScale = 3
        bouncesZoom = true
        delaysContentTouches = false
        canCancelContentTouches = true
        keyboardDismissMode = .interactive
        panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addSubview(column)
        addSubview(footer)
        addButton.addTarget(self, action: #selector(addPage), for: .touchUpInside)
        addButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        addButton.accessibilityLabel = "Add page after the last page"
        footer.addSubview(addButton)
        limitLabel.textAlignment = .center
        limitLabel.font = .preferredFont(forTextStyle: .footnote)
        limitLabel.textColor = .white
        limitLabel.numberOfLines = 2
        footer.addSubview(limitLabel)
        let contact = CanvasNotebookContactRecognizer(target: nil, action: nil)
        contact.onContact = { [weak self] point in self?.activatePage(at: point) }
        addGestureRecognizer(contact)
        accessibilityLabel = "Notebook pages"
        accessibilityHint = "Pinch with two fingers to zoom. Scroll vertically to read more pages."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var pageHeight: CGFloat {
        pageWidth * CanvasPageGeometry.size.height / CanvasPageGeometry.size.width
    }

    func update(pages: [CanvasNotebookPage], isAddingPage: Bool,
                canAddPage: Bool, request: CanvasNotebookScrollRequest?) {
        let oldIDs = self.pages.map(\.id)
        self.pages = pages
        addButton.setTitle(isAddingPage ? "Adding page…" : "Add Page", for: .normal)
        addButton.isEnabled = canAddPage && !isAddingPage
        addButton.tintColor = addButton.isEnabled ? .white : .lightGray
        limitLabel.text = pages.count < CanvasNotebook.maximumPageCount ? "\(pages.count) of \(CanvasNotebook.maximumPageCount) pages"
            : "Maximum \(CanvasNotebook.maximumPageCount) pages"
        if let request, request.id != lastRequestID {
            lastRequestID = request.id
            pendingPageID = request.pageID
        }
        if oldIDs != pages.map(\.id) || pendingPageID != nil { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isLayingOut, bounds.width > 0, !pages.isEmpty else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        if pageWidth != bounds.width {
            let oldHeight = pageHeight + pageGap
            let pagePosition = oldHeight > 0 ? contentOffset.y / (oldHeight * zoomScale) : 0
            pageWidth = bounds.width
            column.bounds.size = CGSize(width: pageWidth,
                height: CGFloat(pages.count) * (pageHeight + pageGap))
            column.frame.origin = .zero
            contentOffset.y = pagePosition * (pageHeight + pageGap) * zoomScale
        } else {
            column.bounds.size.height = CGFloat(pages.count) * (pageHeight + pageGap)
        }
        layoutColumnAndFooter()
        if let id = pendingPageID, let index = pages.firstIndex(where: { $0.id == id }) {
            pendingPageID = nil
            let y = CGFloat(index) * (pageHeight + pageGap) * zoomScale
            setContentOffset(CGPoint(x: contentOffset.x, y: min(y, max(0, contentSize.height - bounds.height))), animated: false)
            publishVisiblePage(index)
        }
        updateSurfaces()
    }

    private func layoutColumnAndFooter() {
        let width = pageWidth * zoomScale
        column.frame.origin = CGPoint(x: max(0, (bounds.width - width) / 2), y: 0)
        let contentWidth = max(bounds.width, width)
        let height = column.bounds.height * zoomScale
        footer.frame = CGRect(x: 0, y: height, width: contentWidth, height: footerHeight)
        // This control stays 44 points high at every zoom level.
        let buttonWidth = min(240, bounds.width - 32)
        let centerX = min(max(contentOffset.x + bounds.width / 2, buttonWidth / 2), contentWidth - buttonWidth / 2)
        addButton.frame = CGRect(x: centerX - buttonWidth / 2, y: 8, width: buttonWidth, height: 44)
        limitLabel.frame = CGRect(x: centerX - buttonWidth / 2, y: 56, width: buttonWidth, height: 44)
        let newSize = CGSize(width: contentWidth, height: height + footerHeight)
        if contentSize != newSize { contentSize = newSize }
    }

    private func pageFrame(at index: Int) -> CGRect {
        CGRect(x: 0, y: CGFloat(index) * (pageHeight + pageGap), width: pageWidth, height: pageHeight)
    }

    /// Keep nearby surfaces alive; keep the store when a surface leaves the viewport.
    private func updateSurfaces() {
        guard pageWidth > 0, !pages.isEmpty else { return }
        let visible = column.convert(bounds, from: self)
        let step = pageHeight + pageGap
        let first = max(0, min(pages.count - 1, Int(floor(visible.minY / step)) - 1))
        let last = max(first, min(pages.count - 1, Int(floor(visible.maxY / step)) + 1))
        let needed = Set(pages[first...last].map(\.id))
        for id in Array(surfaces.keys) where !needed.contains(id) {
            guard let surface = surfaces[id], surface.prepareForRemoval() else { continue }
            surface.removeFromSuperview()
            observations.removeValue(forKey: id)
            surfaces.removeValue(forKey: id)
        }
        for index in first...last {
            let entry = pages[index]
            let surface: CanvasSurfaceView
            if let existing = surfaces[entry.id] {
                surface = existing
            } else {
                surface = CanvasSurfaceView(store: entry.store)
                surfaces[entry.id] = surface
                column.addSubview(surface)
                observations[entry.id] = entry.store.objectWillChange.sink { [weak surface, weak store = entry.store] _ in
                    // Published values change after objectWillChange. Apply once on the next main turn.
                    DispatchQueue.main.async {
                        guard let surface, let store else { return }
                        surface.apply(store.page, tool: store.tool, color: store.color, width: store.inkWidth)
                    }
                }
            }
            let frame = pageFrame(at: index)
            if surface.frame != frame { surface.frame = frame }
            if surface.notebookZoomScale != zoomScale { surface.notebookZoomScale = zoomScale }
            surface.accessibilityLabel = "Page \(index + 1)"
        }
        if !surfaces.values.contains(where: { $0.isInteractingWithPage }) {
            let index = max(0, min(pages.count - 1, Int(floor(visible.midY / step))))
            publishVisiblePage(index)
        }
    }

    private func activatePage(at point: CGPoint) {
        let location = column.convert(point, from: self)
        guard pageHeight > 0 else { return }
        let index = Int(floor(location.y / (pageHeight + pageGap)))
        guard pages.indices.contains(index), pageFrame(at: index).contains(location) else { return }
        publishVisiblePage(index)
    }

    private func publishVisiblePage(_ index: Int) {
        guard lastVisibleIndex != index else { return }
        lastVisibleIndex = index
        DispatchQueue.main.async { [weak self] in self?.onVisiblePageChange?(index) }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer, gestureRecognizer.numberOfTouches < 2 {
            let location = gestureRecognizer.location(in: column)
            for surface in surfaces.values where surface.frame.contains(location) {
                let point = surface.convert(location, from: column)
                if !surface.permitsNotebookPan(at: point) { return false }
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { column }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isLayingOut else { return }
        layoutColumnAndFooter()
        updateSurfaces()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        layoutColumnAndFooter()
        updateSurfaces()
        let percent = Int((zoomScale * 100).rounded())
        if percent != lastZoomPercent {
            lastZoomPercent = percent
            DispatchQueue.main.async { [weak self] in self?.onZoomChange?(percent) }
        }
    }

    func flushSurfaces() {
        for surface in surfaces.values { surface.flushForRemoval() }
    }

    @objc private func addPage() { onAddPage?() }
}

/// Observe contact without recognizing or cancelling a page gesture.
private final class CanvasNotebookContactRecognizer: UIGestureRecognizer {
    var onContact: ((CGPoint) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { onContact?(touch.location(in: view)) }
        state = .failed
    }
}
