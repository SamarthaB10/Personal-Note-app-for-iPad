import Combine
import CoreGraphics
import Foundation
import PencilKit

@MainActor
final class CanvasPageStore: ObservableObject {
    @Published private(set) var page: CanvasPageData
    @Published private(set) var drawingRevision = 0
    @Published var tool: CanvasTool = .pen
    @Published var color: CanvasColor = .black
    @Published var inkWidth: CGFloat = 3
    @Published private(set) var saveStatus = "Loading saved page…"
    @Published private(set) var actionMessage: String?
    @Published private(set) var isSaving = false
    @Published private(set) var canUndoScratch = false
    @Published private(set) var selection = CanvasSelection()
    @Published private(set) var selectionBounds: CGRect?
    @Published private(set) var lassoPreview: [CGPoint] = []
    @Published private(set) var editingTextBoxID: UUID?

    var onFlushCanvasDrawing: (() -> Void)?

    private let fileURL: URL?
    private let saveQueue = DispatchQueue(label: "CanvasPrototype.page-save", qos: .utility)
    private var saveRevision = 0
    private var actionRevision = 0
    private var scratchUndoStack: [[RemovedStroke]] = []
    private var pendingPageSave: DispatchWorkItem?
    private var canSave = true

    private struct RemovedStroke {
        var index: Int
        var stroke: PKStroke
    }

    init() {
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
        guard selection.textBoxIDs.count == 1, let id = selection.textBoxIDs.first else { return nil }
        return page.textBoxes.first(where: { $0.id == id })?.fontSize
    }

    func reloadSavedPage() {
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
            page = try Self.decodeAndValidatePage(from: Data(contentsOf: fileURL))
            canSave = true
            drawingRevision += 1
            scratchUndoStack = []
            canUndoScratch = false
            clearSelection()
            saveStatus = "Saved page reopened locally."
            actionMessage = saveStatus
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
        if let box = page.textBoxes.reversed().first(where: { $0.frame.insetBy(dx: -12, dy: -12).contains(point) }) {
            editingTextBoxID = box.id
            return
        }

        let origin = CGPoint(
            x: min(max(point.x, 28), CanvasPageGeometry.size.width - 250),
            y: min(max(point.y, 28), CanvasPageGeometry.size.height - 100)
        )
        var updated = page
        updated.textBoxes.append(
            CanvasTextBox(text: "New text", frame: CGRect(origin: origin, size: CGSize(width: 220, height: 64)), color: color)
        )
        page = updated
        persist()
    }

    func addRectangle(from start: CGPoint, to end: CGPoint) {
        let frame = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -1, dy: -1)
        guard frame.width >= 12, frame.height >= 12 else { return }
        var updated = page
        updated.shapes.append(CanvasShape(frame: frame, color: color, lineWidth: inkWidth))
        page = updated
        persist()
    }

    func updateTextBox(_ id: UUID, text: String) {
        guard let index = page.textBoxes.firstIndex(where: { $0.id == id }) else { return }
        var updated = page
        updated.textBoxes[index].text = text
        page = updated
        schedulePersist()
    }

    func finishTextEditing() {
        editingTextBoxID = nil
    }

    func updateLassoPreview(_ points: [CGPoint]) {
        lassoPreview = points
    }

    func finishFreehandLasso(_ points: [CGPoint]) {
        selection = CanvasSelectionGeometry.select(
            inside: points,
            drawing: drawing,
            textBoxes: page.textBoxes,
            shapes: page.shapes
        )
        lassoPreview = []
        selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
    }

    func finishBoxLasso(from start: CGPoint, to end: CGPoint) {
        selection = CanvasSelectionGeometry.select(
            in: CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y),
            drawing: drawing,
            textBoxes: page.textBoxes,
            shapes: page.shapes
        )
        lassoPreview = []
        selectionBounds = CanvasSelectionGeometry.bounds(of: selection, in: page)
    }

    func moveSelection(by translation: CGPoint) {
        transformSelection(scale: 1, translation: translation)
    }

    func scaleSelection(by scale: CGFloat) {
        guard let selectionBounds else { return }
        transformSelection(scale: scale, translation: .zero, around: CGPoint(x: selectionBounds.midX, y: selectionBounds.midY))
    }

    func clearSelection() {
        selection = CanvasSelection()
        selectionBounds = nil
        lassoPreview = []
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

    private func writeSnapshot(isUserAction: Bool = false) {
        guard canSave, let fileURL else {
            if fileURL == nil { saveStatus = "Local storage is unavailable." }
            if isUserAction { actionMessage = saveStatus }
            return
        }

        saveRevision += 1
        let revision = saveRevision
        let explicitActionRevision = actionRevision
        let snapshot = page
        saveStatus = "Saving locally…"
        isSaving = true
        saveQueue.async { [weak self] in
            let result: Result<Void, Error>
            do {
                let encoded = try JSONEncoder().encode(snapshot)
                try encoded.write(to: fileURL, options: .atomic)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
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

    private static func decodeAndValidatePage(from data: Data) throws -> CanvasPageData {
        let page = try JSONDecoder().decode(CanvasPageData.self, from: data)
        if page.inkDrawingData.isEmpty {
            guard page.textBoxes.isEmpty, page.shapes.isEmpty else {
                throw SavedPageError.invalidInk
            }
        } else {
            _ = try PKDrawing(data: page.inkDrawingData)
        }
        return page
    }

    private enum SavedPageError: Error {
        case invalidInk
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
