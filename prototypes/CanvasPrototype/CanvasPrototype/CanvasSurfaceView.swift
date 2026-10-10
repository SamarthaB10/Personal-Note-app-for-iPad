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

    static func dismantleUIView(_ view: CanvasSurfaceView, coordinator: ()) {
        view.flushForRemoval()
    }
}

@MainActor
final class CanvasSurfaceView: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    private let logicalSize = CanvasPageGeometry.size
    private let pageView = UIView()
    private let paperView = CanvasPaperBackgroundView()
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
    private var activeShapeKind: CanvasShapeKind?
    private var selectionGesture: SelectionGesture?
    private var selectionDrawingBefore: PKDrawing?
    private var selectionMoveExtent: CGFloat = 0
    private var selectionMoveThreshold: CGFloat = 0
    private var selectionTranslation = CGPoint.zero
    private var selectionScale: CGFloat = 1
    private var selectionAnchor = CGPoint.zero
    private var resizeIsArmed = false
    private var ownsFlushCallback = false
    private var isPreparedForRemoval = false
    var notebookZoomScale: CGFloat = 1 {
        didSet {
            itemView.screenScale = pageScreenScale
            itemView.setNeedsDisplay()
            if selectionGesture == nil { updateSelectionActions() }
        }
    }

    private var pageScreenScale: CGFloat {
        max(0.1, hypot(pageView.transform.a, pageView.transform.b) * notebookZoomScale)
    }

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

        paperView.frame = pageView.bounds
        paperView.isUserInteractionEnabled = false
        pageView.addSubview(paperView)

        backgroundView.frame = pageView.bounds
        backgroundView.contentMode = .scaleToFill
        backgroundView.image = store.showsPrototypeBackground ? Self.loadPDFBackground() : nil
        backgroundView.isUserInteractionEnabled = false
        pageView.addSubview(backgroundView)

        canvasView.frame = pageView.bounds
        canvasView.delegate = self
        // PencilKit must display the saved ink colors in either paper appearance.
        canvasView.overrideUserInterfaceStyle = .light
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

        store.onFlushCanvasDrawing = { [weak self] in
            guard let self, !self.isPreparedForRemoval else { return }
            self.ownsFlushCallback = true
            self.commitPendingDrawing(allowDuringPencil: true)
        }

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CanvasSurfaceView, _: UITraitCollection) in
            view.updatePaperAppearance()
        }

        apply(store.page, tool: store.tool, color: store.color, width: store.inkWidth)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The scroll container keeps this surface attached until input has ended.
    var isInteractingWithPage: Bool {
        isUsingPencil || activePathInput != nil || editor?.isFirstResponder == true
    }

    /// Flush before eviction. A newer surface's callback must remain installed.
    func prepareForRemoval() -> Bool {
        guard !isUsingPencil, !scratchIsRecognized, activePathInput == nil else { return false }
        flushForRemoval()
        return true
    }

    func flushForRemoval() {
        guard !isPreparedForRemoval else { return }
        finishSelectionGesture(cancelled: true)
        resetPagePath()
        if scratchIsRecognized { cancelScratchErase() }
        store.finishTextEditing()
        removeTextEditor()
        commitPendingDrawing(allowDuringPencil: true)
        ownsFlushCallback = false
        store.onFlushCanvasDrawing?()
        if ownsFlushCallback { store.onFlushCanvasDrawing = nil }
        isPreparedForRemoval = true
        canvasView.delegate = nil
        fingerGesture.isEnabled = false
        pencilToolGesture.isEnabled = false
        scratchGesture.isEnabled = false
        pendingDrawingSave?.cancel()
        pendingDrawingSave = nil
    }

    /// Finger paths use page tools. The notebook keeps two-finger pan and pinch available.
    func permitsNotebookPan(at point: CGPoint) -> Bool {
        let pagePoint = pageView.convert(point, from: self)
        if !selectionActions.isHidden, selectionActions.frame.contains(pagePoint) { return false }
        if let editor, editor.frame.contains(pagePoint) { return false }
        if store.tool == .rectangle || store.tool == .freehandLasso
            || store.tool == .boxedLasso || store.tool == .selection {
            return false
        }
        return true
    }

    private func updatePaperAppearance() {
        let hasPDF = backgroundView.image != nil
        pageView.backgroundColor = hasPDF ? .white : .systemBackground
        paperView.paper = store.page.paper
        paperView.isHidden = hasPDF
        paperView.setNeedsDisplay()
        pageView.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        editor?.backgroundColor = hasPDF ? .white : .systemBackground
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(bounds.width / logicalSize.width, bounds.height / logicalSize.height)
        guard scale.isFinite, scale > 0 else { return }
        pageView.bounds = CGRect(origin: .zero, size: logicalSize)
        pageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        pageView.transform = CGAffineTransform(scaleX: scale, y: scale)
        itemView.screenScale = pageScreenScale
        itemView.setNeedsDisplay()
        if selectionGesture == nil { updateSelectionActions() }
    }

    func apply(_ page: CanvasPageData, tool: CanvasTool, color: CanvasColor, width: CGFloat) {
        guard !isPreparedForRemoval else { return }
        updatePaperAppearance()
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
        if activePathTool != .rectangle { itemView.shapePreview = [] }
        itemView.shapePreviewColor = color.uiColor
        itemView.shapePreviewWidth = width
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

        let shouldCaptureFinger = store.canWrite && tool.capturesFingerInput
        let pencilToolEnabled = store.canWrite && (tool == .rectangle || tool == .freehandLasso || tool == .boxedLasso || tool == .selection)
        let shouldUseScratch = store.canWrite && page.scratchEraseEnabled && (tool == .pen || tool == .highlighter)
        let shouldDrawInk = store.canWrite && !pencilToolEnabled
        if pageGestureEnabled != shouldCaptureFinger {
            fingerGesture.isEnabled = shouldCaptureFinger
            pageGestureEnabled = shouldCaptureFinger
        }
        if pencilGestureEnabled != pencilToolEnabled {
            pencilToolGesture.isEnabled = pencilToolEnabled
            pencilGestureEnabled = pencilToolEnabled
        }
        if canvasDrawingEnabled != shouldDrawInk {
            canvasView.drawingGestureRecognizer.isEnabled = shouldDrawInk
            canvasDrawingEnabled = shouldDrawInk
        }
        if scratchGestureEnabled != shouldUseScratch {
            scratchGesture.isEnabled = shouldUseScratch
            scratchGestureEnabled = shouldUseScratch
        }
        updateTextEditor(for: page, editingID: store.canWrite && tool == .textBox ? store.editingTextBoxID : nil)
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
            activeShapeKind = store.shapeKind
            selectionGesture = nil
            switch store.tool {
            case .freehandLasso, .boxedLasso, .selection:
                if beginSelectionGesture(at: point) {
                    activePathTool = .selection
                } else if beginTouchedInkGesture(at: point) {
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
                itemView.shapePreview = CanvasShapeInk.locations(kind: activeShapeKind ?? store.shapeKind,
                                                                 from: start, to: point)
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
                store.addShape(from: start, to: end, kind: activeShapeKind)
            case .freehandLasso, .boxedLasso:
                finishLassoPath(points, start: start, end: end, extent: pathExtent)
            default:
                break
            }
            if selectionGesture != nil {
                updateSelectionGesture(at: end)
                if case .move = selectionGesture,
                   selectionMoveExtent == 0 || (selectionMoveThreshold > 0 && selectionMoveExtent < selectionMoveThreshold) {
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

    /// Allow tap jitter for whole objects. A short ink path still uses contact geometry.
    private func finishLassoPath(_ points: [CGPoint], start: CGPoint, end: CGPoint, extent: CGFloat) {
        if extent < 8 {
            let hit = CanvasSelectionGeometry.selectObject(
                at: start, drawing: canvasView.drawing,
                textBoxes: store.page.textBoxes, shapes: store.page.shapes
            )
            let hasObjectHit = !hit.textBoxIDs.isEmpty || !hit.shapeIDs.isEmpty
            let needsBoxChoice = CanvasSelectionGeometry.textBoxCandidates(at: start, in: store.page.textBoxes).count > 1
            if extent == 0 || hasObjectHit || needsBoxChoice {
                store.selectObject(at: start)
                return
            }
        }
        if activePathTool == .boxedLasso {
            store.finishBoxLasso(from: start, to: end)
        } else {
            store.finishFreehandLasso(points)
        }
    }

    private func resetPagePath() {
        fingerStart = nil
        selectionGesture = nil
        activePathTool = nil
        activePathInput = nil
        activeShapeKind = nil
        itemView.shapePreview = []
        itemView.setNeedsDisplay()
        fingerGesture.recordsFullPath = true
        pencilToolGesture.recordsFullPath = true
        store.updateLassoPreview([])
    }

    private func beginTouchedInkGesture(at point: CGPoint) -> Bool {
        let hit = CanvasSelectionGeometry.selectObject(
            at: point, drawing: canvasView.drawing,
            textBoxes: store.page.textBoxes, shapes: store.page.shapes
        )
        guard !hit.strokeIndices.isEmpty, store.selectTouchedInk(at: point) else { return false }
        // Synchronize overlay selection before the first transform update arrives.
        apply(store.page, tool: store.tool, color: store.color, width: store.inkWidth)
        return beginSelectionGesture(at: point, touchedInk: true)
    }

    /// Start on selected content to drag it. Whitespace remains available for a new loop.
    private func beginSelectionGesture(at point: CGPoint, touchedInk: Bool = false) -> Bool {
        guard let bounds = store.selectionBounds else { return false }
        let resizeHandle = CanvasSelectionHandles.resizeCenter(for: bounds)
        let touchesResizeHandle = hypot(point.x - resizeHandle.x, point.y - resizeHandle.y) <= 18 / pageScreenScale
        // The initial ink hit already chose the top stroke, including at a crossing.
        let touchesSelectedContent = touchedInk || store.directSelectionContains(point)
        guard touchesResizeHandle || touchesSelectedContent else { return false }
        selectionAnchor = CGPoint(x: bounds.midX, y: bounds.midY)
        if !touchedInk && (resizeIsArmed || (touchesResizeHandle && !touchesSelectedContent)) {
            selectionGesture = .resize(startDistance: max(1, hypot(point.x - selectionAnchor.x, point.y - selectionAnchor.y)))
        } else {
            selectionGesture = .move(startPoint: point)
        }
        clearResizeMode()
        fingerGesture.recordsFullPath = false
        pencilToolGesture.recordsFullPath = false
        selectionMoveExtent = 0
        selectionMoveThreshold = store.selection.strokeIndices.isEmpty ? 8 : 0
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
            guard selectionMoveExtent >= selectionMoveThreshold else { return }
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
        let pageScale = pageScreenScale
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
        currentEditor.backgroundColor = backgroundView.image != nil ? .white : .systemBackground
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
    var shapePreview: [CGPoint] = []
    var shapePreviewColor = UIColor.black
    var shapePreviewWidth: CGFloat = 3
    var editingTextBoxID: UUID?
    var screenScale: CGFloat = 1

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

        if shapePreview.count >= 2 {
            context.beginPath()
            context.addLines(between: shapePreview)
            context.setStrokeColor(shapePreviewColor.cgColor)
            context.setLineWidth(shapePreviewWidth)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.strokePath()
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
            let radius = 7 / max(0.1, screenScale)
            let handle = CGRect(x: resizeCenter.x - radius, y: resizeCenter.y - radius, width: radius * 2, height: radius * 2)
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

/// Draw paper in page coordinates. Appearance changes never change stored page content.
private final class CanvasPaperBackgroundView: UIView {
    var paper: CanvasPaper = .blank

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let isDark = traitCollection.userInterfaceStyle == .dark
        context.setFillColor((isDark ? UIColor(white: 0.08, alpha: 1) : .white).cgColor)
        context.fill(bounds)
        guard paper != .blank else { return }
        context.setStrokeColor((isDark ? UIColor(white: 0.28, alpha: 1) : UIColor(white: 0.84, alpha: 1)).cgColor)
        context.setLineWidth(0.5)
        let spacing: CGFloat = paper == .lined ? 28 : 24
        context.beginPath()
        for y in stride(from: spacing, through: bounds.height, by: spacing) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        if paper == .grid {
            for x in stride(from: spacing, through: bounds.width, by: spacing) {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: bounds.height))
            }
        }
        context.strokePath()
    }
}
