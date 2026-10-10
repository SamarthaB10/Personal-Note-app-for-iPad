import Combine
import Foundation
import PencilKit
import UIKit

@MainActor
final class CanvasNotebookStore: ObservableObject {
    @Published private(set) var notebooks: [CanvasNotebook] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isCreating = false
    @Published private(set) var errorMessage: String?

    var canCreateNotebook: Bool { storageIsValid && !isLoading && !isCreating }

    private let directoryURL: URL?
    private let storageQueue = DispatchQueue(label: "PersonalNotes.notebook-storage", qos: .utility)
    private let coverQueue = DispatchQueue(label: "PersonalNotes.notebook-covers", qos: .utility)
    private var coverPages: [UUID: CanvasPageData] = [:]
    private var coverRequests: [UUID: Int] = [:]
    private var lifecycleSaveTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var storageIsValid = false
    private var indexMutationIsActive = false
    private var indexMutationWaiters: [CheckedContinuation<Void, Never>] = []
    private var pageStores: [UUID: [UUID: CanvasPageStore]] = [:]

    init() {
        directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("PersonalNotes", isDirectory: true)
        Task { await loadLibrary() }
    }

    /// The prototype file uses a different directory and is never migrated or replaced.
    private func loadLibrary() async {
        guard let directoryURL else {
            isLoading = false
            errorMessage = "Local storage is unavailable."
            return
        }
        let result: Result<[CanvasNotebook], Error> = await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                    let indexURL = Self.indexURL(in: directoryURL)
                    var library = CanvasNotebookLibrary()
                    if FileManager.default.fileExists(atPath: indexURL.path) {
                        library = try JSONDecoder().decode(CanvasNotebookLibrary.self, from: Data(contentsOf: indexURL))
                        try library.validate()
                    } else {
                        // Do not start a new index over existing notebook directories.
                        let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
                        guard contents.isEmpty else { throw CanvasNotebookStorageError.invalidLibrary }
                    }
                    for index in library.notebooks.indices {
                        let coverURL = Self.notebookURL(library.notebooks[index].id, in: directoryURL)
                            .appendingPathComponent("cover.png")
                        if FileManager.default.fileExists(atPath: coverURL.path) {
                            library.notebooks[index].coverRevision = max(1, library.notebooks[index].coverRevision)
                        }
                    }
                    continuation.resume(returning: .success(library.notebooks))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        isLoading = false
        switch result {
        case .success(let savedNotebooks):
            notebooks = savedNotebooks
            storageIsValid = true
        case .failure:
            errorMessage = "The notebook library could not be opened. Saved files are preserved."
        }
    }

    func createNotebook(title: String) async -> CanvasNotebook? {
        guard canCreateNotebook, let directoryURL else { return nil }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            errorMessage = "Enter a notebook title."
            return nil
        }
        isCreating = true
        await acquireIndexMutation()
        defer {
            releaseIndexMutation()
            isCreating = false
        }
        let notebook = CanvasNotebook(id: UUID(), title: title, folderID: .unfiled,
                                      pageIDs: (0..<7).map { _ in UUID() }, createdAt: Date(), coverRevision: 0)
        let library = CanvasNotebookLibrary(notebooks: notebooks + [notebook])
        let canCreateIndex = notebooks.isEmpty
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    let notebookURL = Self.notebookURL(notebook.id, in: directoryURL)
                    guard !FileManager.default.fileExists(atPath: notebookURL.path) else {
                        throw CanvasNotebookStorageError.invalidLibrary
                    }
                    try FileManager.default.createDirectory(at: notebookURL, withIntermediateDirectories: true)
                    let blankPage = CanvasPageData(inkDrawingData: PKDrawing().dataRepresentation(),
                                                   textBoxes: [], shapes: [], scratchEraseEnabled: true)
                    let encodedPage = try JSONEncoder().encode(blankPage)
                    for pageID in notebook.pageIDs {
                        try encodedPage.write(to: Self.pageURL(pageID, notebookID: notebook.id, in: directoryURL), options: .atomic)
                    }
                    // Publish membership only after all seven editable pages exist.
                    try Self.writeLibrary(library, in: directoryURL, allowMissingIndex: canCreateIndex)
                    continuation.resume(returning: .success(()))
                } catch {
                    // Partial creation files remain available for later recovery.
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch result {
        case .success:
            notebooks.append(notebook)
            errorMessage = nil
            return notebook
        case .failure:
            errorMessage = "The notebook could not be created. Saved files are preserved."
            return nil
        }
    }

    /// Hold the mutation permit across each await, before taking an index snapshot.
    private func acquireIndexMutation() async {
        if !indexMutationIsActive {
            indexMutationIsActive = true
            return
        }
        await withCheckedContinuation { continuation in
            indexMutationWaiters.append(continuation)
        }
    }

    private func releaseIndexMutation() {
        if indexMutationWaiters.isEmpty {
            indexMutationIsActive = false
        } else {
            indexMutationWaiters.removeFirst().resume()
        }
    }

    /// The bottom Add Page control adds a page after the last page.
    func appendPage(to notebookID: UUID) async -> CanvasPageStore? {
        await publishPage(after: nil, in: notebookID)
    }

    /// The header Add Page control adds a page immediately after the current page.
    func insertPage(after pageID: UUID, in notebookID: UUID) async -> CanvasPageStore? {
        await publishPage(after: pageID, in: notebookID)
    }

    /// Hold the permit until the new page and its ordered index entry are saved.
    private func publishPage(after anchorPageID: UUID?, in notebookID: UUID) async -> CanvasPageStore? {
        guard storageIsValid, !isLoading, let directoryURL else { return nil }
        await acquireIndexMutation()
        defer { releaseIndexMutation() }
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            errorMessage = "The notebook could not be found."
            return nil
        }
        if let anchorPageID, !notebooks[index].pageIDs.contains(anchorPageID) {
            errorMessage = "The current page could not be found. Saved files are preserved."
            return nil
        }
        guard notebooks[index].pageIDs.count < CanvasNotebook.maximumPageCount else {
            errorMessage = "This notebook has reached the 300-page limit."
            return nil
        }
        guard await openNotebook(notebookID) != nil else { return nil }
        // Read the current state after opening; cover updates can finish during the await.
        var updatedNotebooks = notebooks
        let insertionIndex: Int
        if let anchorPageID {
            guard let anchorIndex = updatedNotebooks[index].pageIDs.firstIndex(of: anchorPageID) else {
                errorMessage = "The current page could not be found. Saved files are preserved."
                return nil
            }
            insertionIndex = anchorIndex + 1
        } else {
            insertionIndex = updatedNotebooks[index].pageIDs.count
        }
        let pageID = UUID()
        let page = CanvasPageData(inkDrawingData: PKDrawing().dataRepresentation(),
                                  textBoxes: [], shapes: [], scratchEraseEnabled: true,
                                  paper: updatedNotebooks[index].defaultPaper)
        updatedNotebooks[index].pageIDs.insert(pageID, at: insertionIndex)
        let library = CanvasNotebookLibrary(notebooks: updatedNotebooks)
        let fileURL = Self.pageURL(pageID, notebookID: notebookID, in: directoryURL)
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                        throw CanvasNotebookStorageError.invalidLibrary
                    }
                    try JSONEncoder().encode(page).write(to: fileURL, options: .atomic)
                    try Self.writeLibrary(library, in: directoryURL)
                    continuation.resume(returning: .success(()))
                } catch {
                    // An unpublished page is kept for recovery if the index write fails.
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch result {
        case .success:
            let store = CanvasPageStore(page: page, fileURL: fileURL, saveQueue: storageQueue)
            pageStores[notebookID]?[pageID] = store
            notebooks[index].pageIDs.insert(pageID, at: insertionIndex)
            errorMessage = nil
            return store
        case .failure:
            errorMessage = "The page could not be added. Saved files are preserved."
            return nil
        }
    }

    func setDefaultPaper(_ paper: CanvasPaper, for notebookID: UUID) async -> Bool {
        guard storageIsValid, !isLoading, let directoryURL else { return false }
        await acquireIndexMutation()
        defer { releaseIndexMutation() }
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            errorMessage = "The notebook could not be found."
            return false
        }
        guard notebooks[index].defaultPaper != paper else { return true }
        var updatedNotebooks = notebooks
        updatedNotebooks[index].defaultPaper = paper
        let library = CanvasNotebookLibrary(notebooks: updatedNotebooks)
        let succeeded: Bool = await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    try Self.writeLibrary(library, in: directoryURL)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
        if succeeded {
            notebooks[index].defaultPaper = paper
            errorMessage = nil
        } else {
            errorMessage = "The default paper could not be saved. Saved files are preserved."
        }
        return succeeded
    }

    /// Reads and validates every page before exposing editable stores.
    func openNotebook(_ id: UUID) async -> [CanvasPageStore]? {
        guard let notebook = notebooks.first(where: { $0.id == id }), let directoryURL else { return nil }
        if let cached = pageStores[id] {
            return notebook.pageIDs.compactMap { cached[$0] }
        }
        let result: Result<[CanvasPageData], Error> = await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    let pages = try notebook.pageIDs.map { pageID in
                        try CanvasPageStore.decodeAndValidatePage(from: Data(contentsOf:
                            Self.pageURL(pageID, notebookID: id, in: directoryURL)))
                    }
                    continuation.resume(returning: .success(pages))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch result {
        case .success(let pages):
            // An overlapping open request can reuse the first completed stores.
            if let cached = pageStores[id] { return notebook.pageIDs.compactMap { cached[$0] } }
            var stores: [UUID: CanvasPageStore] = [:]
            for (pageID, page) in zip(notebook.pageIDs, pages) {
                stores[pageID] = CanvasPageStore(page: page,
                    fileURL: Self.pageURL(pageID, notebookID: id, in: directoryURL), saveQueue: storageQueue,
                    onSaved: { [weak self] snapshot in
                        if pageID == notebook.pageIDs.first { self?.updateCover(notebookID: id, page: snapshot) }
                    })
            }
            pageStores[id] = stores
            if let firstPage = pages.first { updateCover(notebookID: id, page: firstPage) }
            errorMessage = nil
            return notebook.pageIDs.compactMap { stores[$0] }
        case .failure:
            errorMessage = "The notebook could not be opened. A page is missing or invalid. Saved files are preserved."
            return nil
        }
    }

    func pageStore(notebookID: UUID, pageID: UUID) -> CanvasPageStore? {
        pageStores[notebookID]?[pageID]
    }

    func saveNotebook(_ id: UUID) async -> Bool {
        guard let notebook = notebooks.first(where: { $0.id == id }), let stores = pageStores[id] else { return false }
        var succeeded = true
        for pageID in notebook.pageIDs {
            guard let store = stores[pageID] else { succeeded = false; continue }
            if !(await store.saveForClose()) { succeeded = false }
        }
        if !succeeded {
            errorMessage = "The notebook could not be saved. Keep it open and try again."
        }
        return succeeded
    }

    /// A short native background task lets queued local writes finish on scene exit.
    func saveLifecycleSnapshots() {
        for stores in pageStores.values {
            for store in stores.values { store.saveLifecycleSnapshot() }
        }
        guard lifecycleSaveTask == nil, !pageStores.isEmpty else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save notebook pages") { [weak self] in
            Task { @MainActor [weak self] in self?.endBackgroundSave() }
        }
        let stores = pageStores.values.flatMap { $0.values }
        lifecycleSaveTask = Task { [weak self] in
            for store in stores { _ = await store.saveForClose() }
            self?.endBackgroundSave()
            self?.lifecycleSaveTask = nil
        }
    }

    private func endBackgroundSave() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func coverURL(for notebookID: UUID) -> URL? {
        guard let directoryURL,
              notebooks.contains(where: { $0.id == notebookID && $0.coverRevision > 0 }) else { return nil }
        return Self.notebookURL(notebookID, in: directoryURL).appendingPathComponent("cover.png")
    }

    private func updateCover(notebookID: UUID, page: CanvasPageData) {
        guard let directoryURL else { return }
        if let previous = coverPages[notebookID],
           previous.inkDrawingData == page.inkDrawingData,
           previous.textBoxes == page.textBoxes, previous.shapes == page.shapes,
           previous.paper == page.paper { return }
        coverPages[notebookID] = page
        let request = (coverRequests[notebookID] ?? 0) + 1
        coverRequests[notebookID] = request
        let coverURL = Self.notebookURL(notebookID, in: directoryURL).appendingPathComponent("cover.png")
        // A short quiet period joins several completed saves into one cover request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.coverRequests[notebookID] == request else { return }
            self.coverQueue.async { [weak self] in
                do {
                    let data = try Self.coverData(for: page)
                    try data.write(to: coverURL, options: .atomic)
                    Task { @MainActor [weak self] in
                        guard let self, let index = self.notebooks.firstIndex(where: { $0.id == notebookID }) else { return }
                        self.notebooks[index].coverRevision += 1
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        self?.coverPages[notebookID] = nil
                        self?.errorMessage = "The page was saved, but its notebook cover could not be updated."
                    }
                }
            }
        }
    }

    /// Validate existing data before replacing an index; never replace an invalid file.
    nonisolated private static func writeLibrary(_ library: CanvasNotebookLibrary, in directory: URL,
                                                  allowMissingIndex: Bool = false) throws {
        let url = indexURL(in: directory)
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try JSONDecoder().decode(CanvasNotebookLibrary.self, from: Data(contentsOf: url))
            try existing.validate()
        } else if !allowMissingIndex {
            throw CanvasNotebookStorageError.invalidLibrary
        }
        try library.validate()
        try JSONEncoder().encode(library).write(to: url, options: .atomic)
    }

    nonisolated private static func indexURL(in directory: URL) -> URL {
        directory.appendingPathComponent("library.json")
    }

    nonisolated private static func notebookURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    nonisolated private static func pageURL(_ pageID: UUID, notebookID: UUID, in directory: URL) -> URL {
        notebookURL(notebookID, in: directory).appendingPathComponent(pageID.uuidString + ".json")
    }

    /// Rendering is queued after a completed save, never on each Pencil point.
    nonisolated private static func coverData(for page: CanvasPageData) throws -> Data {
        let pageSize = CanvasPageGeometry.size
        let scale: CGFloat = 180 / pageSize.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 180, height: pageSize.height * scale), format: format).image { renderer in
            let context = renderer.cgContext
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: CGSize(width: 180, height: pageSize.height * scale)))
            context.scaleBy(x: scale, y: scale)
            if page.paper != .blank {
                context.setStrokeColor(UIColor(white: 0.84, alpha: 1).cgColor)
                context.setLineWidth(0.5)
                let spacing: CGFloat = page.paper == .lined ? 28 : 24
                for y in stride(from: spacing, through: pageSize.height, by: spacing) {
                    context.move(to: CGPoint(x: 0, y: y))
                    context.addLine(to: CGPoint(x: pageSize.width, y: y))
                }
                if page.paper == .grid {
                    for x in stride(from: spacing, through: pageSize.width, by: spacing) {
                        context.move(to: CGPoint(x: x, y: 0))
                        context.addLine(to: CGPoint(x: x, y: pageSize.height))
                    }
                }
                context.strokePath()
            }
            let drawing = (try? PKDrawing(data: page.inkDrawingData)) ?? PKDrawing()
            drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: scale)
                .draw(in: CGRect(origin: .zero, size: pageSize))
            for shape in page.shapes {
                context.setStrokeColor(shape.color.uiColor.cgColor)
                context.setLineWidth(shape.lineWidth)
                context.stroke(shape.frame)
            }
            for box in page.textBoxes {
                (box.text as NSString).draw(in: box.frame.insetBy(dx: 5, dy: 5), withAttributes: [
                    .font: UIFont.systemFont(ofSize: box.fontSize), .foregroundColor: box.color.uiColor
                ])
            }
        }
        guard let data = image.pngData() else { throw CanvasNotebookStorageError.invalidLibrary }
        return data
    }

}
