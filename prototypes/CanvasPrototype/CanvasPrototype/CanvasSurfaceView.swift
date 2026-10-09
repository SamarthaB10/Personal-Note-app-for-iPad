import PDFKit
import PencilKit
import SwiftUI
import UIKit

struct CanvasPageView: UIViewRepresentable {
    @ObservedObject var store: CanvasPageStore

    init(store: CanvasPageStore) {
        self.store = store
    }

    func makeUIView(context: Context) -> CanvasSurfaceView {
        CanvasSurfaceView(store: store)
    }

    func updateUIView(_ view: CanvasSurfaceView, context: Context) {
        view.apply(store.page, tool: store.tool, color: store.color, width: store.inkWidth)
    }
}

@MainActor
final class CanvasSurfaceView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    private let logicalSize = CanvasPageGeometry.size
    private let pageView = UIView()
    private let backgroundView = UIImageView()
    private let canvasView = PKCanvasView()
    private let itemView = CanvasItemOverlayView()
    private let store: CanvasPageStore
    private let fingerGesture = CanvasFingerGestureRecognizer()
    private let pencilToolGesture = CanvasFingerGestureRecognizer()
    private let scratchGesture = CanvasScratchGestureRecognizer()

    private var editor: CanvasKeyboardTextView?
    private var editorBoxID: UUID?
    private var configuredTool: CanvasTool?
    private var configuredColor: CanvasColor?
    private var configuredWidth: CGFloat?
    private var lastAppliedDrawingRevision: Int?
    private var pageGestureEnabled: Bool?
    private var pencilGestureEnabled: Bool?
    private var canvasDrawingEnabled: Bool?
    private var scratchGestureEnabled: Bool?
    private var isUsingPencil = false
    private var hasPendingInkChanges = false
    private var isApplyingCanvasDrawing = false
    private var pendingDrawingSave: DispatchWorkItem?
    private var scratchDrawingBefore: PKDrawing?
    private var scratchIsRecognized = false
    private var fingerStart: CGPoint?
    private var lastFingerPoint: CGPoint?
    private var activePathTool: CanvasTool?
    private var selectionGesture: SelectionGesture?

    private enum SelectionGesture {
        case move(lastPoint: CGPoint)
        case resize(lastDistance: CGFloat)
    }

    init(store: CanvasPageStore) {
        self.store = store
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .systemGroupedBackground

        pageView.bounds = CGRect(origin: .zero, size: logicalSize)
        pageView.backgroundColor = .white
        pageView.clipsToBounds = true
        pageView.layer.borderColor = UIColor.separator.cgColor
        pageView.layer.borderWidth = 1
        addSubview(pageView)

        backgroundView.frame = pageView.bounds
        backgroundView.contentMode = .scaleToFill
        backgroundView.image = Self.loadPDFBackground()
        backgroundView.isUserInteractionEnabled = false
        pageView.addSubview(backgroundView)

        canvasView.frame = pageView.bounds
        canvasView.delegate = self
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly
        canvasView.isRulerActive = false
        canvasView.isScrollEnabled = false
        pageView.addSubview(canvasView)

        itemView.frame = pageView.bounds
        itemView.isUserInteractionEnabled = false
        itemView.isOpaque = false
        itemView.backgroundColor = .clear
        pageView.addSubview(itemView)

        fingerGesture.delegate = self
        fingerGesture.onEvent = { [weak self] event in self?.handleFingerEvent(event) }
        pageView.addGestureRecognizer(fingerGesture)

        pencilToolGesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilToolGesture.delegate = self
        pencilToolGesture.onEvent = { [weak self] event in self?.handlePencilToolEvent(event) }
        pageView.addGestureRecognizer(pencilToolGesture)

        scratchGesture.delegate = self
        scratchGesture.onPencilDown = { [weak self] in
            guard let self else { return }
            self.scratchDrawingBefore = self.canvasView.drawing
            self.scratchIsRecognized = false
        }
        scratchGesture.onScratchBegan = { [weak self] _ in
            guard let self else { return }
            self.scratchIsRecognized = true
            self.pendingDrawingSave?.cancel()
            self.pendingDrawingSave = nil
        }
        scratchGesture.onScratchEnded = { [weak self] path in self?.finishScratchErase(path: path) }
        scratchGesture.onScratchCancelled = { [weak self] in self?.cancelScratchErase() }
        pageView.addGestureRecognizer(scratchGesture)

        store.onFlushCanvasDrawing = { [weak self] in self?.commitPendingDrawing(allowDuringPencil: true) }

        apply(store.page, tool: store.tool, color: store.color, width: store.inkWidth)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(bounds.width / logicalSize.width, bounds.height / logicalSize.height)
        guard scale.isFinite, scale > 0 else { return }
        pageView.bounds = CGRect(origin: .zero, size: logicalSize)
        pageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        pageView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    func apply(_ page: CanvasPageData, tool: CanvasTool, color: CanvasColor, width: CGFloat) {
        itemView.page = page
        itemView.selection = store.selection
        itemView.selectionBounds = store.selectionBounds
        itemView.lassoPreview = store.lassoPreview
        itemView.lassoTool = tool
        itemView.shapePreview = nil
        itemView.editingTextBoxID = tool == .textBox ? store.editingTextBoxID : nil
        itemView.setNeedsDisplay()

        applyStoreDrawingIfNeeded(page)

        if configuredTool != tool || configuredColor != color || configuredWidth != width {
            configureInkTool(tool: tool, color: color, width: width)
            configuredTool = tool
            configuredColor = color
            configuredWidth = width
        }

        let shouldCaptureFinger = tool.capturesFingerInput
        let pencilToolEnabled = tool == .rectangle || tool == .freehandLasso || tool == .boxedLasso || tool == .selection
        let shouldUseScratch = page.scratchEraseEnabled && (tool == .pen || tool == .highlighter)
        if pageGestureEnabled != shouldCaptureFinger {
            fingerGesture.isEnabled = shouldCaptureFinger
            pageGestureEnabled = shouldCaptureFinger
        }
        if pencilGestureEnabled != pencilToolEnabled {
            pencilToolGesture.isEnabled = pencilToolEnabled
            pencilGestureEnabled = pencilToolEnabled
        }
        if canvasDrawingEnabled != !pencilToolEnabled {
            canvasView.drawingGestureRecognizer.isEnabled = !pencilToolEnabled
            canvasDrawingEnabled = !pencilToolEnabled
        }
        if scratchGestureEnabled != shouldUseScratch {
            scratchGesture.isEnabled = shouldUseScratch
            scratchGestureEnabled = shouldUseScratch
        }
        updateTextEditor(for: page, editingID: tool == .textBox ? store.editingTextBoxID : nil)
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        isUsingPencil = true
        pendingDrawingSave?.cancel()
        pendingDrawingSave = nil
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isUsingPencil = false
        guard !scratchIsRecognized else { return }
        if hasPendingInkChanges {
            scheduleDrawingSave(after: 0.35)
        } else {
            applyStoreDrawingIfNeeded(store.page)
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingCanvasDrawing, !scratchIsRecognized else { return }
        hasPendingInkChanges = true
        guard !isUsingPencil else { return }
        scheduleDrawingSave(after: 0.35)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === fingerGesture, let editor, touch.view?.isDescendant(of: editor) == true {
            return false
        }
        return true
    }

    private func configureInkTool(tool: CanvasTool, color: CanvasColor, width: CGFloat) {
        switch tool {
        case .pen:
            canvasView.tool = PKInkingTool(.pen, color: color.uiColor, width: width)
        case .highlighter:
            canvasView.tool = PKInkingTool(.marker, color: color.uiColor.withAlphaComponent(0.35), width: width * 3)
        case .partialEraser:
            canvasView.tool = PKEraserTool(.bitmap)
        case .objectEraser:
            canvasView.tool = PKEraserTool(.vector)
        case .textBox, .rectangle, .freehandLasso, .boxedLasso, .selection:
            canvasView.tool = PKInkingTool(.pen, color: color.uiColor, width: width)
        }
    }

    private func setCanvasDrawing(_ drawing: PKDrawing) {
        isApplyingCanvasDrawing = true
        canvasView.drawing = drawing
        isApplyingCanvasDrawing = false
    }

    private func applyStoreDrawingIfNeeded(_ page: CanvasPageData) {
        guard
            lastAppliedDrawingRevision != store.drawingRevision,
            !hasPendingInkChanges,
            !isUsingPencil
        else {
            return
        }

        let incomingDrawing = (try? PKDrawing(data: page.inkDrawingData)) ?? PKDrawing()
        setCanvasDrawing(incomingDrawing)
        lastAppliedDrawingRevision = store.drawingRevision
    }

    private func scheduleDrawingSave(after delay: TimeInterval) {
        pendingDrawingSave?.cancel()
        let save = DispatchWorkItem { [weak self] in
            guard let self, !self.isUsingPencil, !self.scratchIsRecognized else { return }
            self.commitPendingDrawing()
        }
        pendingDrawingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: save)
    }

    private func commitPendingDrawing(allowDuringPencil: Bool = false) {
        pendingDrawingSave?.cancel()
        pendingDrawingSave = nil
        guard hasPendingInkChanges, allowDuringPencil || !isUsingPencil else { return }
        let drawing = canvasView.drawing
        hasPendingInkChanges = false
        store.updateDrawing(drawing)
        lastAppliedDrawingRevision = store.drawingRevision
    }

    private func finishScratchErase(path: [CGPoint]) {
        pendingDrawingSave?.cancel()
        pendingDrawingSave = nil
        guard let drawingBefore = scratchDrawingBefore else {
            scratchIsRecognized = false
            return
        }

        store.updateDrawing(drawingBefore)
        let filtered = store.scratchErase(
            drawingBefore: drawingBefore,
            path: path,
            radius: max(13, store.inkWidth * 2.5)
        )
        setCanvasDrawing(filtered)
        lastAppliedDrawingRevision = store.drawingRevision
        hasPendingInkChanges = false
        scratchDrawingBefore = nil
        scratchIsRecognized = false
    }

    private func cancelScratchErase() {
        pendingDrawingSave?.cancel()
        pendingDrawingSave = nil
        guard scratchIsRecognized, let drawingBefore = scratchDrawingBefore else {
            scratchIsRecognized = false
            scratchDrawingBefore = nil
            return
        }
        store.updateDrawing(drawingBefore)
        setCanvasDrawing(drawingBefore)
        lastAppliedDrawingRevision = store.drawingRevision
        hasPendingInkChanges = false
        scratchIsRecognized = false
        scratchDrawingBefore = nil
    }

    private func handleFingerEvent(_ event: CanvasFingerGestureEvent) {
        switch event {
        case let .began(point):
            commitPendingDrawing()
            fingerStart = point
            lastFingerPoint = point
            activePathTool = store.tool
            selectionGesture = nil
            switch store.tool {
            case .freehandLasso, .boxedLasso:
                if beginSelectionGesture(at: point, clearOutsideSelection: false) {
                    activePathTool = .selection
                } else {
                    store.updateLassoPreview([point])
                }
            case .selection:
                beginSelectionGesture(at: point)
            default:
                break
            }
        case let .changed(points):
            guard let start = fingerStart, let point = points.last else { return }
            switch activePathTool ?? store.tool {
            case .rectangle:
                itemView.shapePreview = CGRect(x: start.x, y: start.y, width: point.x - start.x, height: point.y - start.y).standardized
                itemView.setNeedsDisplay()
            case .freehandLasso:
                store.updateLassoPreview(points)
            case .boxedLasso:
                store.updateLassoPreview([start, point])
            case .selection:
                updateSelectionGesture(at: point)
            default:
                break
            }
        case let .ended(points):
            guard let start = fingerStart else { return }
            let end = points.last ?? start
            let moved = hypot(end.x - start.x, end.y - start.y)
            switch activePathTool ?? store.tool {
            case .textBox where moved < 8:
                store.addTextBox(at: start)
            case .rectangle:
                store.addRectangle(from: start, to: end)
            case .freehandLasso:
                store.finishFreehandLasso(points)
            case .boxedLasso:
                store.finishBoxLasso(from: start, to: end)
            default:
                break
            }
            itemView.shapePreview = nil
            itemView.setNeedsDisplay()
            fingerStart = nil
            lastFingerPoint = nil
            selectionGesture = nil
            activePathTool = nil
        case .cancelled:
            fingerStart = nil
            lastFingerPoint = nil
            selectionGesture = nil
            activePathTool = nil
            itemView.shapePreview = nil
            itemView.setNeedsDisplay()
            store.updateLassoPreview([])
        }
    }

    private func handlePencilToolEvent(_ event: CanvasFingerGestureEvent) {
        switch event {
        case let .began(point):
            commitPendingDrawing()
            fingerStart = point
            lastFingerPoint = point
            activePathTool = store.tool
            selectionGesture = nil
            if store.tool == .freehandLasso || store.tool == .boxedLasso {
                if beginSelectionGesture(at: point, clearOutsideSelection: false) {
                    activePathTool = .selection
                } else {
                    store.updateLassoPreview([point])
                }
            } else if store.tool == .selection {
                beginSelectionGesture(at: point)
            }
        case let .changed(points):
            guard let start = fingerStart, let point = points.last else { return }
            switch activePathTool ?? store.tool {
            case .rectangle:
                itemView.shapePreview = CGRect(x: start.x, y: start.y, width: point.x - start.x, height: point.y - start.y).standardized
                itemView.setNeedsDisplay()
            case .freehandLasso:
                store.updateLassoPreview(points)
            case .boxedLasso:
                store.updateLassoPreview([start, point])
            case .selection:
                updateSelectionGesture(at: point)
            default:
                break
            }
        case let .ended(points):
            guard let start = fingerStart else { return }
            let end = points.last ?? start
            switch activePathTool ?? store.tool {
            case .rectangle:
                store.addRectangle(from: start, to: end)
            case .freehandLasso:
                store.finishFreehandLasso(points)
            case .boxedLasso:
                store.finishBoxLasso(from: start, to: end)
            default:
                break
            }
            itemView.shapePreview = nil
            itemView.setNeedsDisplay()
            fingerStart = nil
            lastFingerPoint = nil
            selectionGesture = nil
            activePathTool = nil
        case .cancelled:
            fingerStart = nil
            lastFingerPoint = nil
            selectionGesture = nil
            activePathTool = nil
            itemView.shapePreview = nil
            itemView.setNeedsDisplay()
            store.updateLassoPreview([])
        }
    }

    @discardableResult
    private func beginSelectionGesture(at point: CGPoint, clearOutsideSelection: Bool = true) -> Bool {
        guard let bounds = store.selectionBounds else { return false }
        let handle = CGPoint(x: bounds.maxX, y: bounds.maxY)
        if hypot(point.x - handle.x, point.y - handle.y) <= 18 {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let distance = max(1, hypot(point.x - center.x, point.y - center.y))
            selectionGesture = .resize(lastDistance: distance)
            return true
        } else if bounds.insetBy(dx: -14, dy: -14).contains(point) {
            selectionGesture = .move(lastPoint: point)
            return true
        } else {
            if clearOutsideSelection { store.clearSelection() }
            return false
        }
    }

    private func updateSelectionGesture(at point: CGPoint) {
        switch selectionGesture {
        case let .move(lastPoint):
            store.moveSelection(by: CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y))
            selectionGesture = .move(lastPoint: point)
        case let .resize(lastDistance):
            guard let bounds = store.selectionBounds else { return }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let distance = max(1, hypot(point.x - center.x, point.y - center.y))
            store.scaleSelection(by: distance / max(1, lastDistance))
            selectionGesture = .resize(lastDistance: distance)
        case nil:
            break
        }
    }

    private func updateTextEditor(for page: CanvasPageData, editingID: UUID?) {
        guard
            let editingID,
            let box = page.textBoxes.first(where: { $0.id == editingID })
        else {
            if let editor {
                editor.resignFirstResponder()
                editor.removeFromSuperview()
            }
            editor = nil
            editorBoxID = nil
            return
        }

        let currentEditor: CanvasKeyboardTextView
        if let editor, editorBoxID == editingID {
            currentEditor = editor
        } else {
            editor?.resignFirstResponder()
            editor?.removeFromSuperview()

            let newEditor = CanvasKeyboardTextView(frame: box.frame, textContainer: nil)
            newEditor.onTextChange = { [weak store] text in store?.updateTextBox(editingID, text: text) }
            newEditor.onEditingEnd = { [weak self] in
                guard self?.store.editingTextBoxID == editingID else { return }
                self?.store.finishTextEditing()
            }
            pageView.addSubview(newEditor)
            editor = newEditor
            editorBoxID = editingID
            currentEditor = newEditor
            DispatchQueue.main.async { [weak newEditor] in
                newEditor?.becomeFirstResponder()
            }
        }

        currentEditor.frame = box.frame
        currentEditor.font = .systemFont(ofSize: box.fontSize)
        currentEditor.textColor = box.color.uiColor
        if !currentEditor.isFirstResponder, currentEditor.text != box.text {
            currentEditor.text = box.text
        }
    }

    private static func loadPDFBackground() -> UIImage? {
        guard
            let url = Bundle.main.url(forResource: "fixed-background", withExtension: "pdf"),
            let page = PDFDocument(url: url)?.page(at: 0)
        else {
            return nil
        }
        return page.thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox)
    }
}

private final class CanvasItemOverlayView: UIView {
    var page = CanvasPageData.empty
    var selection = CanvasSelection()
    var selectionBounds: CGRect?
    var lassoPreview: [CGPoint] = []
    var lassoTool: CanvasTool = .pen
    var shapePreview: CGRect?
    var editingTextBoxID: UUID?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clear(rect)
        for shape in page.shapes {
            context.setStrokeColor(shape.color.uiColor.cgColor)
            context.setLineWidth(shape.lineWidth)
            context.stroke(shape.frame)
            if selection.shapeIDs.contains(shape.id) {
                context.setStrokeColor(UIColor.systemBlue.cgColor)
                context.setLineWidth(2)
                context.stroke(shape.renderBounds.insetBy(dx: -4, dy: -4))
            }
        }

        for box in page.textBoxes where box.id != editingTextBoxID {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: box.fontSize),
                .foregroundColor: box.color.uiColor
            ]
            (box.text as NSString).draw(in: box.frame.insetBy(dx: 5, dy: 5), withAttributes: attributes)
            if selection.textBoxIDs.contains(box.id) {
                context.setStrokeColor(UIColor.systemBlue.cgColor)
                context.setLineWidth(2)
                context.stroke(box.frame.insetBy(dx: -3, dy: -3))
            }
        }

        if let shapePreview {
            context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(shapePreview)
            context.setLineDash(phase: 0, lengths: [])
        }

        if lassoTool == .boxedLasso, lassoPreview.count >= 2 {
            let start = lassoPreview[0]
            let end = lassoPreview[lassoPreview.count - 1]
            let box = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y).standardized
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(box)
            context.setLineDash(phase: 0, lengths: [])
        } else if lassoPreview.count > 1 {
            context.beginPath()
            context.addLines(between: lassoPreview)
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }

        if let selectionBounds {
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(selectionBounds.insetBy(dx: -4, dy: -4))
            context.setLineDash(phase: 0, lengths: [])
            let handle = CGRect(x: selectionBounds.maxX - 7, y: selectionBounds.maxY - 7, width: 14, height: 14)
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: handle)
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.strokeEllipse(in: handle)
        }
    }
}

private extension CanvasColor {
    var uiColor: UIColor {
        switch self {
        case .black: .black
        case .blue: .systemBlue
        case .red: .systemRed
        case .green: .systemGreen
        }
    }
}
