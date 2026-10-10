import Combine
import CoreGraphics
import Foundation
import PencilKit

@MainActor
final class CanvasPageStore: ObservableObject {
    @Published private(set) var page: CanvasPageData
    @Published private(set) var drawingRevision = 0
    var tool: CanvasTool {
        get { toolSettings.tool }
        set { toolSettings.tool = newValue }
    }
    var color: CanvasColor {
        get { toolSettings.color }
        set { toolSettings.color = newValue }
    }
    var inkWidth: CGFloat {
        get { toolSettings.inkWidth }
        set { toolSettings.setWidth(newValue) }
    }
    var shapeKind: CanvasShapeKind {
        get { toolSettings.shapeKind }
        set { toolSettings.shapeKind = newValue }
    }
    var textFontSize: CGFloat {
        get { toolSettings.textFontSize }
        set { toolSettings.setTextFontSize(newValue) }
    }
    var rememberedEraserTool: CanvasTool { toolSettings.rememberedEraserTool }
    var rememberedLassoTool: CanvasTool { toolSettings.rememberedLassoTool }
    @Published private(set) var saveStatus = "Loading saved page…"
    @Published private(set) var actionMessage: String?
    @Published private(set) var isSaving = false
    @Published private(set) var canUndoScratch = false
    @Published private(set) var selection = CanvasSelection()
    @Published private(set) var selectionBounds: CGRect?
    @Published private(set) var lassoPreview: [CGPoint] = []
    @Published private(set) var editingTextBoxID: UUID?
    @Published private(set) var selectionOutline: [CGPoint] = []
    @Published private(set) var textBoxCandidates: [CanvasTextBox] = []
    @Published private(set) var previewTextBoxID: UUID?

    var textBoxChoiceStartsEditing: Bool { textBoxChoiceIntent == .edit }


    var onFlushCanvasDrawing: (() -> Void)?
    var notebookDirectoryURL: URL? { showsPrototypeBackground ? nil : fileURL?.deletingLastPathComponent() }
    let showsPrototypeBackground: Bool

    private let toolSettings = CanvasToolSettings.shared
    private var toolSubscriptions: Set<AnyCancellable> = []
    private let fileURL: URL?
    private let saveQueue: DispatchQueue
    private let onSaved: ((CanvasPageData) -> Void)?
    private let validatesSavedFile: Bool
    private var saveRevision = 0
    private var actionRevision = 0
    private var scratchUndoStack: [[RemovedStroke]] = []
    private var pendingPageSave: DispatchWorkItem?
    private var canSave = true
    private var textBoxChoiceIntent: TextBoxChoiceIntent?
    private var selectionTransform: SelectionTransform?

    private enum TextBoxChoiceIntent { case edit, select }

    private struct SelectionTransform {
        var page: CanvasPageData
        var selection: CanvasSelection
        var outline: [CGPoint]
        var anchor: CGPoint
        var changed = false
    }

    private struct RemovedStroke {
        var index: Int
        var stroke: PKStroke
    }

    init() {
        saveQueue = DispatchQueue(label: "CanvasPrototype.page-save", qos: .utility)
        onSaved = nil
        showsPrototypeBackground = true
        validatesSavedFile = false
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let supportURL {
            let directory = supportURL.appendingPathComponent("CanvasPrototype", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                fileURL = directory.appendingPathComponent("prototype-page.json")
            } catch {
                fileURL = nil
                saveStatus = "Local storage is unavailable."
            }
        } else {
            fileURL = nil
            saveStatus = "Local storage is unavailable."
        }

        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                page = try Self.decodeAndValidatePage(from: Data(contentsOf: fileURL))
                saveStatus = "Saved page opened locally."
            } catch {
                page = Self.samplePage()
                canSave = false
                saveStatus = "Saved page data is invalid. The file is preserved."
            }
        } else {
            page = Self.samplePage()
            persist()
        }
        drawingRevision = 1
        observeToolSettings()
        convertLoadedShapesToInk()
    }

    /// Notebook pages arrive from the validated local store, without prototype fixtures.
    init(page: CanvasPageData, fileURL: URL, saveQueue: DispatchQueue,
         onSaved: ((CanvasPageData) -> Void)? = nil) {
        self.page = page
        self.fileURL = fileURL
        self.saveQueue = saveQueue
        self.onSaved = onSaved
        showsPrototypeBackground = false
        validatesSavedFile = true
        saveStatus = "Saved page opened locally."
        drawingRevision = 1
        observeToolSettings()
        convertLoadedShapesToInk()
    }

    private func observeToolSettings() {
        toolSettings.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &toolSubscriptions)
        toolSettings.$tool.dropFirst().removeDuplicates().sink { [weak self] tool in
            self?.cancelTextBoxChoice()
            if tool != .textBox { self?.finishTextEditing() }
        }.store(in: &toolSubscriptions)
    }

    /// The library waits for this write before it closes a notebook.
    func saveForClose() async -> Bool {
        while true {
            onFlushCanvasDrawing?()
            pendingPageSave?.cancel()
            pendingPageSave = nil
            let snapshot = page
            let succeeded = await withCheckedContinuation { continuation in
                writeSnapshot { success in continuation.resume(returning: success) }
            }
            guard succeeded else { return false }
            // Ink can finish while the write is in progress. Save that change as well.
            if page.inkDrawingData == snapshot.inkDrawingData,
               page.textBoxes == snapshot.textBoxes, page.shapes == snapshot.shapes,
               page.scratchEraseEnabled == snapshot.scratchEraseEnabled,
               page.paper == snapshot.paper, page.importedBackground == snapshot.importedBackground { return true }
        }
    }

    var drawing: PKDrawing {
        guard !page.inkDrawingData.isEmpty else { return PKDrawing() }
        do {
            return try PKDrawing(data: page.inkDrawingData)
        } catch {
            canSave = false
            saveStatus = "Saved page data is invalid. The file is preserved."
            return PKDrawing()
        }
    }

    var canWrite: Bool {
        canSave && fileURL != nil
    }

    var hasSaveError: Bool {
        !canWrite || saveStatus == "Local save failed."
    }

    var selectionSummary: String {
        "\(selection.strokeIndices.count) ink · \(selection.textBoxIDs.count) text boxes · \(selection.shapeIDs.count) shapes"
    }

    var selectedTextFontSize: CGFloat? {
        selectedTextBox?.fontSize
    }

    /// Individual text actions are unavailable for a mixed or multiple-box selection.
    var selectedTextBox: CanvasTextBox? {
        guard selection.strokeIndices.isEmpty, selection.shapeIDs.isEmpty,
              selection.textBoxIDs.count == 1, let id = selection.textBoxIDs.first else { return nil }
        return page.textBoxes.first(where: { $0.id == id })
    }

    var formattingTextBox: CanvasTextBox? {
        guard textBoxCandidates.isEmpty, selectionTransform == nil else { return nil }
        if let editingTextBoxID {
            return page.textBoxes.first(where: { $0.id == editingTextBoxID })
        }
        return selectedTextBox
    }

    func reloadSavedPage() {
        cancelTextBoxChoice()
        endSelectionTransform(cancelled: true)
        actionRevision += 1
        actionMessage = "Reopening page…"
        onFlushCanvasDrawing?()
        guard let fileURL else {
            saveStatus = "Local storage is unavailable."
            actionMessage = saveStatus
            return
        }
        pendingPageSave?.cancel()
        pendingPageSave = nil

        do {
            _ = try Self.decodeAndValidatePage(from: Data(contentsOf: fileURL))
        } catch {
            canSave = false
            saveStatus = "Saved page data is invalid. The file is preserved."
            actionMessage = saveStatus
            return
        }

        // Keep queued save completions from replacing the result of Reopen.
        saveRevision += 1
        if canSave {
            let snapshot = page
            do {
                try saveQueue.sync {
                    let encoded = try JSONEncoder().encode(snapshot)
                    try encoded.write(to: fileURL, options: .atomic)
                }
            } catch {
                isSaving = false
                saveStatus = "Local save failed."
                actionMessage = "Reopen failed because the page could not be saved. Your current page stays open."
                return
            }
        } else {
            saveQueue.sync {}
        }
        isSaving = false
        do {
            page = try Self.convertingShapesToInk(in: Self.decodeAndValidatePage(from: Data(contentsOf: fileURL)))
            canSave = true
            drawingRevision += 1
            scratchUndoStack = []
            canUndoScratch = false
            clearSelection()
            saveStatus = "Saved page reopened locally."
            actionMessage = saveStatus
            persist()
        } catch {
            canSave = false
            saveStatus = "Saved page data is invalid. The file is preserved."
            actionMessage = saveStatus
        }
    }

    func saveNow() {
        actionRevision += 1
        actionMessage = "Saving page…"
        onFlushCanvasDrawing?()
        pendingPageSave?.cancel()
        pendingPageSave = nil
        writeSnapshot(isUserAction: true)
    }

    /// Flushes ink when the scene becomes inactive without changing button feedback.
    func saveLifecycleSnapshot() {
        onFlushCanvasDrawing?()
        persist()
    }

    func setPaper(_ paper: CanvasPaper) {
        guard page.paper != paper else { return }
        onFlushCanvasDrawing?()
        var updated = page
        updated.paper = paper
        page = updated
        persist()
    }

    func setScratchEraseEnabled(_ enabled: Bool) {
        var updated = page
        updated.scratchEraseEnabled = enabled
        page = updated
        persist()
    }

    func updateDrawing(_ drawing: PKDrawing) {
        let drawingData = drawing.dataRepresentation()
        guard drawingData != page.inkDrawingData else { return }
        let previousStrokes = self.drawing.strokes
        let hasPreviousPrefix = drawing.strokes.count >= previousStrokes.count
        let prefixMatches = hasPreviousPrefix && (
            previousStrokes.isEmpty
                || PKDrawing(strokes: previousStrokes).dataRepresentation()
                    == PKDrawing(strokes: Array(drawing.strokes.prefix(previousStrokes.count))).dataRepresentation()
        )
        if !prefixMatches { clearScratchUndoHistory() }
        var updated = page
        updated.inkDrawingData = drawingData
        page = updated
        drawingRevision += 1
        clearSelection()
        schedulePersist()
    }

    func addTextBox(at point: CGPoint) {
        guard canWrite, point.x.isFinite, point.y.isFinite else { return }
        cancelTextBoxChoice()
        let candidates = CanvasSelectionGeometry.textBoxCandidates(at: point, in: page.textBoxes)
        if candidates.count > 1 {
            startTextBoxChoice(candidates, intent: .edit)
            return
        }
        if let box = candidates.first {
            if box.frame.contains(point) {
                editingTextBoxID = box.id
            } else {
                startTextBoxChoice(candidates, intent: .edit)
            }
            return
        }

        let origin = CGPoint(
            x: min(max(point.x, 28), CanvasPageGeometry.size.width - 250),
            y: min(max(point.y, 28), CanvasPageGeometry.size.height - 100)
        )
        var updated = page
        updated.textBoxes.append(
            CanvasTextBox(text: "New text", frame: CGRect(origin: origin, size: CGSize(width: 220, height: 64)),
                          fontSize: textFontSize, color: color)
        )
        page = updated
        persist()
    }

    func previewTextBoxChoice(_ id: UUID) {
        guard textBoxCandidates.contains(where: { $0.id == id }) else { return }
        previewTextBoxID = id
    }

    func chooseTextBox(_ id: UUID) {
        guard canWrite, textBoxCandidates.contains(where: { $0.id == id }),
              page.textBoxes.contains(where: { $0.id == id }),
              let intent = textBoxChoiceIntent else { return }
        cancelTextBoxChoice()
        if intent == .edit {
            editingTextBoxID = id
        } else {
            finishTextEditing()
            selection = CanvasSelection(textBoxIDs: [id])
            selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
            selectionOutline = []
            lassoPreview = []
        }
    }

    func cancelTextBoxChoice() {
        textBoxCandidates = []
        previewTextBoxID = nil
        textBoxChoiceIntent = nil
    }

    private func startTextBoxChoice(_ candidates: [CanvasTextBox], intent: TextBoxChoiceIntent) {
        textBoxCandidates = candidates
        previewTextBoxID = nil
        textBoxChoiceIntent = intent
    }

    /// Appends one complete ink stroke. The native erasers need no shape-specific path.
    func addShape(from start: CGPoint, to end: CGPoint, kind: CanvasShapeKind? = nil) {
        guard canWrite else { return }
        let kind = kind ?? shapeKind
        let locations = CanvasShapeInk.locations(kind: kind, from: start, to: end)
        guard let first = locations.first,
              locations.contains(where: { hypot($0.x - first.x, $0.y - first.y) >= 12 }),
              (kind == .arrow || kind == .line
               || (abs(end.x - start.x) >= 12 && abs(end.y - start.y) >= 12)),
              let stroke = CanvasShapeInk.stroke(locations: locations, color: color,
                                                width: inkWidth, smooth: kind == .circle || kind == .ellipse) else { return }
        onFlushCanvasDrawing?()
        var strokes = drawing.strokes
        strokes.append(stroke)
        updateDrawing(PKDrawing(strokes: strokes))
    }

    /// Convert only a fully validated loaded page. Failed conversion preserves its file.
    private func convertLoadedShapesToInk() {
        guard canSave, !page.shapes.isEmpty else { return }
        do {
            let converted = try Self.convertingShapesToInk(in: page)
            page = converted
            drawingRevision += 1
            persist()
        } catch {
            canSave = false
            saveStatus = "Saved shapes could not become ink. The file is preserved."
        }
    }

    nonisolated private static func convertingShapesToInk(in page: CanvasPageData) throws -> CanvasPageData {
        try validatePage(page)
        guard !page.shapes.isEmpty else { return page }
        let existing = try PKDrawing(data: page.inkDrawingData)
        var strokes = existing.strokes
        for shape in page.shapes {
            // The legacy model supports rectangles only. Keep its exact frame and width.
            let locations = CanvasShapeInk.locations(kind: .rectangle, from: shape.frame.origin,
                                                     to: CGPoint(x: shape.frame.maxX, y: shape.frame.maxY))
            guard let stroke = CanvasShapeInk.stroke(locations: locations, color: shape.color,
                                                     width: shape.lineWidth) else {
                throw SavedPageError.invalidObjects
            }
            strokes.append(stroke)
        }
        var converted = page
        let ink = PKDrawing(strokes: strokes).dataRepresentation()
        guard try PKDrawing(data: ink).strokes.count == strokes.count else {
            throw SavedPageError.invalidInk
        }
        converted.inkDrawingData = ink
        converted.shapes = []
        try validatePage(converted)
        return converted
    }

    func updateTextBox(_ id: UUID, text: String) {
        guard canWrite, let index = page.textBoxes.firstIndex(where: { $0.id == id }) else { return }
        var updated = page
        updated.textBoxes[index].text = text
        page = updated
        schedulePersist()
    }

    /// Format one existing box without changing its edit session or future tool settings.
    func setTextBoxFontSize(_ id: UUID, size: CGFloat) {
        guard canWrite, size.isFinite, (8...96).contains(size),
              formattingTextBox?.id == id,
              let index = page.textBoxes.firstIndex(where: { $0.id == id }),
              page.textBoxes[index].fontSize != size else { return }
        var updated = page
        updated.textBoxes[index].fontSize = size
        page = updated
        schedulePersist()
    }

    func setTextBoxColor(_ id: UUID, color: CanvasColor) {
        guard canWrite, formattingTextBox?.id == id,
              let index = page.textBoxes.firstIndex(where: { $0.id == id }),
              page.textBoxes[index].color != color else { return }
        var updated = page
        updated.textBoxes[index].color = color
        page = updated
        schedulePersist()
    }

    /// Only the explicit Edit action may focus the selected text box.
    func editSelectedTextBox() {
        guard canWrite, selectionTransform == nil, textBoxCandidates.isEmpty,
              let box = selectedTextBox else { return }
        clearSelection()
        tool = .textBox
        editingTextBoxID = box.id
    }

    func finishTextEditing() {
        editingTextBoxID = nil
    }

    func updateLassoPreview(_ points: [CGPoint]) {
        lassoPreview = points
    }

    /// Initial lasso contact selects one complete stroke for immediate movement.
    func selectTouchedInk(at point: CGPoint) -> Bool {
        onFlushCanvasDrawing?()
        let touched = CanvasSelectionGeometry.selectInk(at: point, drawing: drawing)
        guard !touched.isEmpty else { return false }
        cancelTextBoxChoice()
        finishTextEditing()
        selection = touched
        selectionOutline = []
        lassoPreview = []
        selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
        return true
    }

    func selectObject(at point: CGPoint) {
        onFlushCanvasDrawing?()
        cancelTextBoxChoice()
        let candidates = CanvasSelectionGeometry.textBoxCandidates(at: point, in: page.textBoxes)
        if candidates.count > 1 {
            startTextBoxChoice(candidates, intent: .select)
            return
        }
        finishTextEditing()
        selection = candidates.first.map { CanvasSelection(textBoxIDs: [$0.id]) }
            ?? CanvasSelectionGeometry.selectObject(
            at: point,
            drawing: drawing,
            textBoxes: page.textBoxes,
            shapes: page.shapes
        )
        lassoPreview = []
        selectionOutline = []
        selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
    }

    func finishFreehandLasso(_ points: [CGPoint]) {
        cancelTextBoxChoice()
        selection = CanvasSelectionGeometry.select(
            inside: points,
            drawing: drawing,
            textBoxes: page.textBoxes,
            shapes: page.shapes
        )
        selectionOutline = selection.isEmpty ? [] : points
        lassoPreview = []
        selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
    }

    func finishBoxLasso(from start: CGPoint, to end: CGPoint) {
        cancelTextBoxChoice()
        selection = CanvasSelectionGeometry.select(
            in: CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y),
            drawing: drawing,
            textBoxes: page.textBoxes,
            shapes: page.shapes
        )
        selectionOutline = selection.isEmpty ? [] : [
            start, CGPoint(x: end.x, y: start.y), end, CGPoint(x: start.x, y: end.y)
        ]
        lassoPreview = []
        selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
    }

    func directSelectionContains(_ point: CGPoint) -> Bool {
        guard !selection.isEmpty, textBoxCandidates.isEmpty else { return false }
        return CanvasSelectionGeometry.directSelectionContains(point, selection: selection, in: page)
    }

    /// The surface previews the drag locally. This snapshot supports one final transform.
    func beginSelectionTransform() {
        guard canWrite, selectionTransform == nil else { return }
        onFlushCanvasDrawing?()
        guard let bounds = selectionBounds, !selection.isEmpty else { return }
        selectionTransform = SelectionTransform(
            page: page, selection: selection, outline: selectionOutline,
            anchor: CGPoint(x: bounds.midX, y: bounds.midY)
        )
    }

    /// Translation and scale are cumulative from the initial snapshot; this does not save.
    func updateSelectionTransform(translation: CGPoint, scale: CGFloat) {
        guard canWrite, var snapshot = selectionTransform, translation.x.isFinite,
              translation.y.isFinite, scale.isFinite else { return }
        page = CanvasSelectionGeometry.transformed(
            snapshot.page, selection: snapshot.selection, scale: scale,
            translation: translation, around: snapshot.anchor
        )
        selectionOutline = transformedOutline(snapshot.outline, scale: scale, translation: translation, around: snapshot.anchor)
        selectionBounds = CanvasSelectionGeometry.bounds(of: snapshot.selection, in: page)
        snapshot.changed = translation != .zero || scale != 1
        selectionTransform = snapshot
        if !snapshot.selection.strokeIndices.isEmpty { drawingRevision += 1 }
    }

    func endSelectionTransform(cancelled: Bool) {
        guard let snapshot = selectionTransform else { return }
        selectionTransform = nil
        if cancelled {
            page = snapshot.page
            selection = snapshot.selection
            selectionOutline = snapshot.outline
            selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
            if snapshot.changed, !selection.strokeIndices.isEmpty { drawingRevision += 1 }
        } else if snapshot.changed {
            if !selection.strokeIndices.isEmpty { clearScratchUndoHistory() }
            persist()
        }
    }

    private func transformedOutline(_ points: [CGPoint], scale: CGFloat, translation: CGPoint, around anchor: CGPoint) -> [CGPoint] {
        let scale = max(0.25, min(scale, 4))
        return points.map { point in
            CGPoint(x: anchor.x + (point.x - anchor.x) * scale + translation.x,
                    y: anchor.y + (point.y - anchor.y) * scale + translation.y)
        }
    }

    func moveSelection(by translation: CGPoint) {
        transformSelection(scale: 1, translation: translation)
    }

    func scaleSelection(by scale: CGFloat) {
        guard let selectionBounds else { return }
        transformSelection(scale: scale, translation: .zero, around: CGPoint(x: selectionBounds.midX, y: selectionBounds.midY))
    }

    func clearSelection() {
        cancelTextBoxChoice()
        selectionTransform = nil
        selectionOutline = []
        selection = CanvasSelection()
        selectionBounds = nil
        lassoPreview = []
    }

    /// Removes complete selected objects while retaining any newly flushed ink.
    func deleteSelection() {
        guard canWrite else { return }
        let selected = selection
        let inkDataBeforeFlush = page.inkDrawingData
        onFlushCanvasDrawing?()
        guard !selected.isEmpty else { return }

        let currentDrawing = drawing
        let inkChangedDuringFlush = page.inkDrawingData != inkDataBeforeFlush
        // Selected indices are safe only while the stored drawing stays unchanged.
        let removableIndices = inkChangedDuringFlush ? Set<Int>() : Set(
            selected.strokeIndices.filter { currentDrawing.strokes.indices.contains($0) }
        )
        var updated = page
        if !removableIndices.isEmpty {
            updated.inkDrawingData = CanvasSelectionGeometry.removingStrokes(removableIndices, from: currentDrawing).dataRepresentation()
            clearScratchUndoHistory()
        }
        updated.textBoxes.removeAll { selected.textBoxIDs.contains($0.id) }
        updated.shapes.removeAll { selected.shapeIDs.contains($0.id) }
        if let editingTextBoxID, selected.textBoxIDs.contains(editingTextBoxID) {
            finishTextEditing()
        }
        page = updated
        if !removableIndices.isEmpty { drawingRevision += 1 }
        clearSelection()
        persist()
        if inkChangedDuringFlush, !selected.strokeIndices.isEmpty {
            actionRevision += 1
            actionMessage = "Ink changed before Delete. Ink was kept. Select the ink again to delete it."
        }
    }

    func scratchErase(drawingBefore: PKDrawing, path: [CGPoint], radius: CGFloat) -> PKDrawing {
        let removedIndices = CanvasSelectionGeometry.strokesTouched(by: path, radius: radius, in: drawingBefore)
        guard !removedIndices.isEmpty else { return drawingBefore }

        let removedStrokes = removedIndices.sorted().compactMap { index in
            drawingBefore.strokes.indices.contains(index)
                ? RemovedStroke(index: index, stroke: drawingBefore.strokes[index])
                : nil
        }
        guard !removedStrokes.isEmpty else { return drawingBefore }
        scratchUndoStack.append(removedStrokes)
        canUndoScratch = true
        let remaining = CanvasSelectionGeometry.removingStrokes(removedIndices, from: drawingBefore)
        var updated = page
        updated.inkDrawingData = remaining.dataRepresentation()
        page = updated
        drawingRevision += 1
        clearSelection()
        persist()
        return remaining
    }

    func undoLastScratchErase() {
        onFlushCanvasDrawing?()
        guard let removedStrokes = scratchUndoStack.popLast() else { return }
        var strokes = drawing.strokes
        for removed in removedStrokes.sorted(by: { $0.index < $1.index }) {
            strokes.insert(removed.stroke, at: min(removed.index, strokes.count))
        }
        canUndoScratch = !scratchUndoStack.isEmpty
        var updated = page
        updated.inkDrawingData = PKDrawing(strokes: strokes).dataRepresentation()
        page = updated
        drawingRevision += 1
        clearSelection()
        persist()
    }

    private func transformSelection(scale: CGFloat, translation: CGPoint, around anchor: CGPoint = .zero) {
        guard canWrite else { return }
        onFlushCanvasDrawing?()
        guard !selection.isEmpty else { return }
        page = CanvasSelectionGeometry.transformed(
            page,
            selection: selection,
            scale: scale,
            translation: translation,
            around: anchor
        )
        if !selection.strokeIndices.isEmpty {
            drawingRevision += 1
            clearScratchUndoHistory()
        }
        selectionOutline = transformedOutline(selectionOutline, scale: scale, translation: translation, around: anchor)
        selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
        persist()
    }

    private func schedulePersist() {
        pendingPageSave?.cancel()
        let save = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPageSave = nil
            self.writeSnapshot()
        }
        pendingPageSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: save)
    }

    private func persist() {
        pendingPageSave?.cancel()
        pendingPageSave = nil
        writeSnapshot()
    }

    private func writeSnapshot(isUserAction: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard canSave, let fileURL else {
            if fileURL == nil { saveStatus = "Local storage is unavailable." }
            if isUserAction { actionMessage = saveStatus }
            completion?(false)
            return
        }

        saveRevision += 1
        let revision = saveRevision
        let explicitActionRevision = actionRevision
        let snapshot = page
        let validatesSavedFile = validatesSavedFile
        saveStatus = "Saving locally…"
        isSaving = true
        saveQueue.async { [weak self] in
            let result: Result<Void, Error>
            do {
                if validatesSavedFile {
                    _ = try Self.decodeAndValidatePage(from: Data(contentsOf: fileURL))
                }
                let encoded = try JSONEncoder().encode(snapshot)
                try encoded.write(to: fileURL, options: .atomic)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            Task { @MainActor [weak self] in
                guard let self else { completion?(false); return }
                let succeeded: Bool
                switch result {
                case .success: succeeded = true
                case .failure: succeeded = false
                }
                completion?(succeeded)
                if succeeded { self.onSaved?(snapshot) }
                if isUserAction, self.actionRevision == explicitActionRevision {
                    switch result {
                    case .success:
                        self.actionMessage = "Page saved locally."
                    case .failure:
                        self.actionMessage = "The page could not be saved. Your current page stays open."
                    }
                }
                guard self.saveRevision == revision else { return }
                self.isSaving = false
                switch result {
                case .success:
                    self.saveStatus = "Saved locally."
                case .failure:
                    self.saveStatus = "Local save failed."
                }
            }
        }
    }

    private func clearScratchUndoHistory() {
        scratchUndoStack = []
        canUndoScratch = false
    }

    nonisolated static func decodeAndValidatePage(from data: Data) throws -> CanvasPageData {
        let page = try JSONDecoder().decode(CanvasPageData.self, from: data)
        try validatePage(page)
        return page
    }

    nonisolated private static func validatePage(_ page: CanvasPageData) throws {
        try page.importedBackground?.validate()
        let objectIDs = page.textBoxes.map(\.id) + page.shapes.map(\.id)
        guard Set(objectIDs).count == objectIDs.count,
              page.textBoxes.allSatisfy({ box in
                  isValidFrame(box.frame) && box.fontSize.isFinite && box.fontSize > 0
              }),
              page.shapes.allSatisfy({ shape in
                  isValidFrame(shape.frame) && shape.lineWidth.isFinite && shape.lineWidth > 0
              }) else { throw SavedPageError.invalidObjects }
        if page.inkDrawingData.isEmpty {
            guard page.textBoxes.isEmpty, page.shapes.isEmpty else {
                throw SavedPageError.invalidInk
            }
        } else {
            _ = try PKDrawing(data: page.inkDrawingData)
        }
    }

    nonisolated private static func isValidFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0
    }

    private enum SavedPageError: Error {
        case invalidInk
        case invalidObjects
    }

    private static func samplePage() -> CanvasPageData {
        CanvasPageData(
            inkDrawingData: sampleDrawing().dataRepresentation(),
            textBoxes: [
                CanvasTextBox(
                    text: "Tap this box to edit with the keyboard.",
                    frame: CGRect(x: 48, y: 110, width: 420, height: 72),
                    fontSize: 19
                )
            ],
            shapes: [
                CanvasShape(frame: CGRect(x: 64, y: 520, width: 180, height: 92), color: .blue)
            ],
            scratchEraseEnabled: true
        )
    }

    private static func sampleDrawing() -> PKDrawing {
        let points = [
            CGPoint(x: 74, y: 298), CGPoint(x: 84, y: 280), CGPoint(x: 94, y: 316),
            CGPoint(x: 104, y: 284), CGPoint(x: 114, y: 313), CGPoint(x: 124, y: 294),
            CGPoint(x: 136, y: 301), CGPoint(x: 148, y: 300)
        ].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.025,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: 1.2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(
            ink: PKInk(.pen, color: UIColor.label),
            path: path,
            transform: .identity,
            mask: nil
        )
        return PKDrawing(strokes: [stroke])
    }
}
