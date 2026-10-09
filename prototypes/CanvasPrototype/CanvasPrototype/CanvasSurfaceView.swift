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
    private let selectionInkView = UIImageView()
    private let textBoxHighlightView = CanvasTextBoxHighlightView()
    private let selectionActions = UIStackView()
    private var actionWidthConstraints: [NSLayoutConstraint] = []
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
    private var activePathInput: PagePathInput?
    private var activePathTool: CanvasTool?
    private var selectionGesture: SelectionGesture?
    private var selectionDrawingBefore: PKDrawing?
    private var selectionMoveExtent: CGFloat = 0
    private var selectionTranslation = CGPoint.zero
    private var selectionScale: CGFloat = 1
    private var selectionAnchor = CGPoint.zero
    private var resizeIsArmed = false

    private enum PagePathInput {
        case finger
        case pencil
    }

    private enum SelectionGesture {
        case move(startPoint: CGPoint)
        case resize(startDistance: CGFloat)
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

        selectionInkView.frame = pageView.bounds
        selectionInkView.isUserInteractionEnabled = false
        selectionInkView.isHidden = true
        pageView.addSubview(selectionInkView)

        itemView.frame = pageView.bounds
        itemView.isUserInteractionEnabled = false
        itemView.isOpaque = false
        itemView.backgroundColor = .clear
        pageView.addSubview(itemView)

        textBoxHighlightView.frame = pageView.bounds
        textBoxHighlightView.isUserInteractionEnabled = false
        textBoxHighlightView.isOpaque = false
        textBoxHighlightView.backgroundColor = .clear
        pageView.addSubview(textBoxHighlightView)

        configureSelectionActions()
        pageView.addSubview(selectionActions)

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
        if selectionGesture == nil { updateSelectionActions() }
    }

    func apply(_ page: CanvasPageData, tool: CanvasTool, color: CanvasColor, width: CGFloat) {
        if selectionGesture != nil,
           configuredTool != tool || itemView.selection != store.selection {
            finishSelectionGesture(cancelled: true)
            resetPagePath()
            return
        }
        if itemView.selection != store.selection { clearResizeMode() }
        itemView.page = page
        itemView.selection = store.selection
        itemView.selectionBounds = store.selectionBounds
        itemView.selectionOutline = store.selectionOutline
        itemView.lassoPreview = store.lassoPreview
        itemView.lassoTool = tool
        itemView.shapePreview = nil
        itemView.editingTextBoxID = tool == .textBox ? store.editingTextBoxID : nil
        itemView.setNeedsDisplay()

        if selectionGesture == nil {
            applyStoreDrawingIfNeeded(page)
            updateSelectionActions()
        }

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
        textBoxHighlightView.highlightFrame = page.textBoxes.first { $0.id == store.previewTextBoxID }?.frame
        textBoxHighlightView.setNeedsDisplay()
        pageView.bringSubviewToFront(textBoxHighlightView)
        pageView.bringSubviewToFront(selectionActions)
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
        if touch.view?.isDescendant(of: selectionActions) == true { return false }
        if gestureRecognizer === fingerGesture {
            if activePathInput == .pencil { return false }
            if let editor, touch.view?.isDescendant(of: editor) == true { return false }
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
        handlePagePath(event, input: .finger)
    }

    private func handlePencilToolEvent(_ event: CanvasFingerGestureEvent) {
        handlePagePath(event, input: .pencil)
    }

    /// One input owns the path. Pencil input takes priority over a resting finger.
    private func handlePagePath(_ event: CanvasFingerGestureEvent, input: PagePathInput) {
        switch event {
        case let .began(point):
            if activePathInput != nil {
                guard input == .pencil, activePathInput == .finger else { return }
                finishSelectionGesture(cancelled: true)
                resetPagePath()
            }
            activePathInput = input
            commitPendingDrawing()
            fingerStart = point
            activePathTool = store.tool
            selectionGesture = nil
            switch store.tool {
            case .freehandLasso, .boxedLasso, .selection:
                if beginSelectionGesture(at: point) {
                    activePathTool = .selection
                } else {
                    clearResizeMode()
                    store.clearSelection()
                    store.updateLassoPreview([point])
                }
            default:
                break
            }
        case let .changed(points):
            guard activePathInput == input, let start = fingerStart, let point = points.last else { return }
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
            guard activePathInput == input, let start = fingerStart else { return }
            let end = points.last ?? start
            let pathExtent = points.map { hypot($0.x - start.x, $0.y - start.y) }.max() ?? 0
            switch activePathTool ?? store.tool {
            case .textBox where pathExtent < 8:
                store.addTextBox(at: start)
            case .rectangle:
                store.addRectangle(from: start, to: end)
            case .freehandLasso where pathExtent < 8, .boxedLasso where pathExtent < 8:
                store.selectObject(at: start)
            case .freehandLasso:
                store.finishFreehandLasso(points)
            case .boxedLasso:
                store.finishBoxLasso(from: start, to: end)
            default:
                break
            }
            if selectionGesture != nil {
                updateSelectionGesture(at: end)
                if case .move = selectionGesture, selectionMoveExtent < 8 {
                    // Restore the full drawing before selectObject flushes live ink.
                    finishSelectionGesture(cancelled: true)
                    if CanvasSelectionGeometry.textBoxCandidates(at: start, in: store.page.textBoxes).count > 1 {
                        store.selectObject(at: start)
                    }
                } else {
                    finishSelectionGesture(cancelled: false)
                }
            }
            resetPagePath()
        case .cancelled:
            guard activePathInput == input else { return }
            finishSelectionGesture(cancelled: true)
            resetPagePath()
        }
    }

    private func resetPagePath() {
        fingerStart = nil
        selectionGesture = nil
        activePathTool = nil
        activePathInput = nil
        itemView.shapePreview = nil
        itemView.setNeedsDisplay()
        fingerGesture.recordsFullPath = true
        pencilToolGesture.recordsFullPath = true
        store.updateLassoPreview([])
    }

    /// Start on selected content to drag it. Whitespace remains available for a new loop.
    private func beginSelectionGesture(at point: CGPoint) -> Bool {
        guard let bounds = store.selectionBounds else { return false }
        let resizeHandle = CanvasSelectionHandles.resizeCenter(for: bounds)
        let touchesResizeHandle = hypot(point.x - resizeHandle.x, point.y - resizeHandle.y) <= 18
        let touchesSelectedContent = store.directSelectionContains(point)
        guard touchesResizeHandle || touchesSelectedContent else { return false }
        selectionAnchor = CGPoint(x: bounds.midX, y: bounds.midY)
        if resizeIsArmed || (touchesResizeHandle && !touchesSelectedContent) {
            selectionGesture = .resize(startDistance: max(1, hypot(point.x - selectionAnchor.x, point.y - selectionAnchor.y)))
        } else {
            selectionGesture = .move(startPoint: point)
        }
        clearResizeMode()
        fingerGesture.recordsFullPath = false
        pencilToolGesture.recordsFullPath = false
        selectionMoveExtent = 0
        selectionTranslation = .zero
        selectionScale = 1
        store.beginSelectionTransform()
        selectionDrawingBefore = canvasView.drawing
        let selected = store.selection.strokeIndices
        let strokes = canvasView.drawing.strokes
        if !selected.isEmpty {
            let selectedDrawing = PKDrawing(strokes: strokes.enumerated().compactMap { selected.contains($0.offset) ? $0.element : nil })
            selectionInkView.image = selectedDrawing.image(from: pageView.bounds, scale: 2)
            selectionInkView.isHidden = false
            setCanvasDrawing(PKDrawing(strokes: strokes.enumerated().compactMap { selected.contains($0.offset) ? nil : $0.element }))
        }
        selectionActions.isHidden = true
        return true
    }

    /// UIKit previews each move. The editable page changes once when the path ends.
    private func updateSelectionGesture(at point: CGPoint) {
        switch selectionGesture {
        case let .move(startPoint):
            let translation = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            selectionMoveExtent = max(selectionMoveExtent, hypot(translation.x, translation.y))
            guard selectionMoveExtent >= 8 else { return }
            selectionTranslation = translation
        case let .resize(startDistance):
            let distance = max(1, hypot(point.x - selectionAnchor.x, point.y - selectionAnchor.y))
            selectionScale = max(0.25, min(4, distance / startDistance))
        case nil:
            return
        }
        let transform = CGAffineTransform(
            a: selectionScale, b: 0, c: 0, d: selectionScale,
            tx: selectionAnchor.x * (1 - selectionScale) + selectionTranslation.x,
            ty: selectionAnchor.y * (1 - selectionScale) + selectionTranslation.y
        )
        // UIView applies its transform around its center; convert the page-space offset.
        let center = selectionInkView.center
        selectionInkView.transform = CGAffineTransform(
            a: transform.a, b: 0, c: 0, d: transform.d,
            tx: transform.tx + center.x * (selectionScale - 1),
            ty: transform.ty + center.y * (selectionScale - 1)
        )
        itemView.selectionTransform = transform
        itemView.setNeedsDisplay()
    }

    private func finishSelectionGesture(cancelled: Bool) {
        guard selectionGesture != nil else { return }
        if !cancelled {
            store.updateSelectionTransform(translation: selectionTranslation, scale: selectionScale)
        }
        store.endSelectionTransform(cancelled: cancelled)
        selectionGesture = nil
        clearResizeMode()
        selectionInkView.isHidden = true
        selectionInkView.image = nil
        selectionInkView.transform = .identity
        itemView.selectionTransform = .identity
        if cancelled, let selectionDrawingBefore { setCanvasDrawing(selectionDrawingBefore) }
        self.selectionDrawingBefore = nil
        apply(store.page, tool: store.tool, color: store.color, width: store.inkWidth)
    }

    private func configureSelectionActions() {
        selectionActions.axis = .horizontal
        selectionActions.spacing = 0
        selectionActions.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        selectionActions.layer.cornerRadius = 16
        selectionActions.clipsToBounds = true
        for (title, action) in [("Resize", #selector(armSelectionResize)), ("Delete", #selector(deleteSelectedItems)), ("Clear", #selector(clearSelectedItems))] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.setTitleColor(title == "Delete" ? .systemRed : .label, for: .normal)
            button.addTarget(self, action: action, for: .touchUpInside)
            let width = button.widthAnchor.constraint(equalToConstant: 64)
            width.isActive = true
            actionWidthConstraints.append(width)
            selectionActions.addArrangedSubview(button)
        }
    }

    private func updateSelectionActions() {
        let tool = store.tool
        let showsSelection = tool == .freehandLasso || tool == .boxedLasso || tool == .selection
        guard showsSelection, let bounds = store.selectionBounds else {
            selectionActions.isHidden = true
            clearResizeMode()
            return
        }
        let outlineBounds = store.selectionOutline.reduce(bounds) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.1, height: 0.1))) }
        let pageScale = max(0.1, hypot(pageView.transform.a, pageView.transform.b))
        let buttonWidth = 44 / pageScale
        let height = 44 / pageScale
        let width = buttonWidth * 3
        actionWidthConstraints.forEach { $0.constant = buttonWidth }
        selectionActions.layer.cornerRadius = 16 / pageScale
        for case let button as UIButton in selectionActions.arrangedSubviews {
            button.titleLabel?.font = .systemFont(ofSize: 13 / pageScale, weight: .semibold)
        }
        let x = min(max(outlineBounds.midX - width / 2, 4), logicalSize.width - width - 4)
        let y = outlineBounds.minY >= height + 8 ? outlineBounds.minY - height - 6 : min(outlineBounds.maxY + 8, logicalSize.height - height - 4)
        selectionActions.frame = CGRect(x: x, y: y, width: width, height: height)
        selectionActions.isHidden = false
    }

    private func clearResizeMode() {
        resizeIsArmed = false
        selectionActions.arrangedSubviews.first?.accessibilityValue = nil
        selectionActions.arrangedSubviews.first?.backgroundColor = .clear
    }

    @objc private func armSelectionResize() {
        resizeIsArmed = true
        selectionActions.arrangedSubviews.first?.accessibilityValue = "Drag selected content to resize"
        selectionActions.arrangedSubviews.first?.backgroundColor = .systemBlue.withAlphaComponent(0.15)
    }

    @objc private func deleteSelectedItems() {
        store.deleteSelection()
        apply(store.page, tool: store.tool, color: store.color, width: store.inkWidth)
    }

    @objc private func clearSelectedItems() {
        store.clearSelection()
        apply(store.page, tool: store.tool, color: store.color, width: store.inkWidth)
    }

    private func updateTextEditor(for page: CanvasPageData, editingID: UUID?) {
        guard
            let editingID,
            let box = page.textBoxes.first(where: { $0.id == editingID })
        else {
            removeTextEditor()
            return
        }

        let currentEditor: CanvasKeyboardTextView
        if let editor, editorBoxID == editingID {
            currentEditor = editor
        } else {
            removeTextEditor()

            let newEditor = CanvasKeyboardTextView(frame: box.frame, textContainer: nil)
            newEditor.onTextChange = { [weak self, weak newEditor] text in
                guard let self, let newEditor, self.editor === newEditor,
                      self.store.editingTextBoxID == editingID else { return }
                self.store.updateTextBox(editingID, text: text)
            }
            pageView.addSubview(newEditor)
            editor = newEditor
            editorBoxID = editingID
            currentEditor = newEditor
            DispatchQueue.main.async { [weak self, weak newEditor] in
                guard let self, let newEditor, self.editor === newEditor,
                      self.store.editingTextBoxID == editingID,
                      self.store.tool == .textBox, newEditor.window != nil else { return }
                newEditor.becomeFirstResponder()
            }
        }

        if currentEditor.frame != box.frame { currentEditor.frame = box.frame }
        let font = UIFont.systemFont(ofSize: box.fontSize)
        if currentEditor.font != font { currentEditor.font = font }
        let color = box.color.uiColor
        if currentEditor.textColor != color { currentEditor.textColor = color }
        if !currentEditor.isFirstResponder, currentEditor.text != box.text {
            currentEditor.text = box.text
        }
    }

    /// Store actions end the edit session. A UIKit focus change does not remove its text box.
    private func removeTextEditor() {
        let previousEditor = editor
        editor = nil
        editorBoxID = nil
        previousEditor?.onTextChange = nil
        previousEditor?.resignFirstResponder()
        previousEditor?.removeFromSuperview()
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
    var selectionOutline: [CGPoint] = []
    var selectionTransform = CGAffineTransform.identity
    var lassoPreview: [CGPoint] = []
    var lassoTool: CanvasTool = .pen
    var shapePreview: CGRect?
    var editingTextBoxID: UUID?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clear(rect)
        let showsObjectBounds = lassoTool == .freehandLasso || lassoTool == .boxedLasso || lassoTool == .selection
        for shape in page.shapes {
            context.saveGState()
            if selection.shapeIDs.contains(shape.id) { context.concatenate(selectionTransform) }
            context.setStrokeColor(shape.color.uiColor.cgColor)
            context.setLineWidth(shape.lineWidth)
            context.stroke(shape.frame)
            if showsObjectBounds, selection.shapeIDs.contains(shape.id) {
                drawObjectBounds(shape.renderBounds, in: context)
            }
            context.restoreGState()
        }

        for box in page.textBoxes where box.id != editingTextBoxID {
            context.saveGState()
            if selection.textBoxIDs.contains(box.id) { context.concatenate(selectionTransform) }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: box.fontSize),
                .foregroundColor: box.color.uiColor
            ]
            (box.text as NSString).draw(in: box.frame.insetBy(dx: 5, dy: 5), withAttributes: attributes)
            if showsObjectBounds, selection.textBoxIDs.contains(box.id) {
                drawObjectBounds(box.frame, in: context)
            }
            context.restoreGState()
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

        if showsObjectBounds, let selectionBounds {
            context.saveGState()
            context.concatenate(selectionTransform)
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            if selectionOutline.count >= 3 {
                context.beginPath()
                context.addLines(between: selectionOutline)
                context.closePath()
                context.strokePath()
            } else {
                context.stroke(selectionBounds.insetBy(dx: -4, dy: -4))
            }
            context.setLineDash(phase: 0, lengths: [])
            let resizeCenter = CanvasSelectionHandles.resizeCenter(for: selectionBounds)
            let handle = CGRect(x: resizeCenter.x - 7, y: resizeCenter.y - 7, width: 14, height: 14)
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: handle)
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.strokeEllipse(in: handle)
            context.restoreGState()
        }
    }

    private func drawObjectBounds(_ bounds: CGRect, in context: CGContext) {
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [])
        context.stroke(bounds)
        context.setLineDash(phase: 0, lengths: [])
    }
}

/// Chooser feedback stays above the editor without receiving touches or changing focus.
private final class CanvasTextBoxHighlightView: UIView {
    var highlightFrame: CGRect?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clear(rect)
        guard let highlightFrame else { return }
        context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.18).cgColor)
        context.fill(highlightFrame)
        context.setStrokeColor(UIColor.systemOrange.cgColor)
        context.setLineWidth(3)
        context.stroke(highlightFrame)
    }
}

/// Shares the drawn handle positions with their touch targets.
private enum CanvasSelectionHandles {
    static func resizeCenter(for bounds: CGRect) -> CGPoint {
        let pageSize = CanvasPageGeometry.size
        let x = bounds.maxX + 26 <= pageSize.width - 10 ? bounds.maxX + 26 : bounds.minX - 26
        let y = bounds.maxY + 26 <= pageSize.height - 10 ? bounds.maxY + 26 : bounds.minY - 26
        return CGPoint(
            x: min(max(x, 10), pageSize.width - 10),
            y: min(max(y, 10), pageSize.height - 10)
        )
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
