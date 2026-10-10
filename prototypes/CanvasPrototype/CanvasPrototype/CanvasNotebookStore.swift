import Combine
import Foundation
import PencilKit
import UIKit

@MainActor
final class CanvasNotebookStore: ObservableObject, CanvasImportPublishing {
    @Published private(set) var notebooks: [CanvasNotebook] = []
    @Published private(set) var trash: [CanvasTrashRecord] = []
    @Published private(set) var isChangingTrash = false
    @Published private(set) var folders: [CanvasFolder] = []
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
    private var libraryRevision = 0
    private var hasPublishedIndex = false
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
        let result: Result<CanvasNotebookLibrary, Error> = await withCheckedContinuation { continuation in
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
                    continuation.resume(returning: .success(library))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        isLoading = false
        switch result {
        case .success(let library):
            notebooks = library.notebooks
            folders = library.folders
            trash = library.trash
            libraryRevision = library.revision
            hasPublishedIndex = FileManager.default.fileExists(atPath: Self.indexURL(in: directoryURL).path)
            storageIsValid = true
        case .failure:
            errorMessage = "The notebook library could not be opened. Saved files are preserved."
        }
    }

    func createNotebook(title: String, folderID: CanvasFolderID = .unfiled) async -> CanvasNotebook? {
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
        guard containsFolder(folderID) else {
            errorMessage = "The folder could not be found. Saved files are preserved."
            return nil
        }
        let notebook = CanvasNotebook(id: UUID(), title: title, folderID: folderID,
                                      pageIDs: (0..<7).map { _ in UUID() }, createdAt: Date(), coverRevision: 0)
        let library = CanvasNotebookLibrary(notebooks: notebooks + [notebook], folders: folders, revision: libraryRevision + 1, trash: trash)
        let canCreateIndex = !hasPublishedIndex
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
            libraryRevision = library.revision
            hasPublishedIndex = true
            notebooks.append(notebook)
            errorMessage = nil
            return notebook
        case .failure:
            errorMessage = "The notebook could not be created. Saved files are preserved."
            return nil
        }
    }

    var importAdapter: CanvasImportAdapter {
        CanvasImportAdapter(stagingRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalNotesImports", isDirectory: true))
    }

    func existingPageCount(for destination: CanvasImportDestination) throws -> Int {
        guard storageIsValid, !isLoading else { throw CanvasImportError.ioFailure }
        switch destination {
        case .newNotebook(let folderID):
            guard containsFolder(folderID) else { throw CanvasImportError.ioFailure }
            return 0
        case .insertPDF(let id, let anchor):
            guard let notebook = notebooks.first(where: { $0.id == id }), notebook.pageIDs.contains(anchor) else {
                throw CanvasImportError.ioFailure
            }
            return notebook.pageIDs.count
        }
    }

    /// The FIFO permit covers all page/source writes and the atomic index commit.
    func publishImport(_ prepared: CanvasPreparedImport, to destination: CanvasImportDestination,
                       title: String) async throws -> CanvasImportPublication {
        guard storageIsValid, !isLoading, let directoryURL else { throw CanvasImportError.ioFailure }
        await acquireIndexMutation()
        defer { releaseIndexMutation() }
        try Task.checkCancellation()
        var notebook: CanvasNotebook
        let anchor: UUID?
        let existingIndex: Int?
        switch destination {
        case .newNotebook(let folderID):
            guard containsFolder(folderID) else { throw CanvasImportError.ioFailure }
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw CanvasImportError.ioFailure }
            notebook = CanvasNotebook(id: UUID(), title: name, folderID: folderID, pageIDs: [],
                                      createdAt: Date(), coverRevision: 0)
            anchor = nil
            existingIndex = nil
        case .insertPDF(let id, let pageID):
            guard prepared.pages.allSatisfy({ $0.kind == .pdf }),
                  let index = notebooks.firstIndex(where: { $0.id == id }) else { throw CanvasImportError.ioFailure }
            notebook = notebooks[index]
            anchor = pageID
            existingIndex = index
        }
        let plan = try CanvasImportInsertionPlan.make(prepared: prepared, currentPageIDs: notebook.pageIDs, after: anchor)
        notebook.pageIDs = plan.orderedPageIDs
        var publishedSource = prepared.staged.source
        publishedSource.displayAssetNames = plan.newPages.filter { $0.background.kind == .pdf }.map { $0.background.displayAssetName }
        notebook.sources.append(publishedSource)
        var updated = notebooks
        if let existingIndex { updated[existingIndex] = notebook } else { updated.append(notebook) }
        let library = CanvasNotebookLibrary(notebooks: updated, folders: folders, revision: libraryRevision + 1, trash: trash)
        let allowMissing = !hasPublishedIndex
        let notebookID = notebook.id
        let sourceRecord = publishedSource
        let pages = plan.newPages.map { entry in
            CanvasPageData(inkDrawingData: PKDrawing().dataRepresentation(), textBoxes: [], shapes: [], scratchEraseEnabled: true,
                           importedBackground: entry.background)
        }
        let cancellation = CanvasImportCancellation()
        let result: Result<Void, Error> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    try cancellation.check()
                    let directory = Self.notebookURL(notebookID, in: directoryURL)
                    try CanvasImportedContent.createDirectory(directory, in: directoryURL)
                    let sourceDirectory = CanvasImportedContent.sourceDirectory(notebookDirectory: directory)
                    try CanvasImportedContent.createDirectory(sourceDirectory, in: directory)
                    // Flat generated names permit exact resource cleanup for Trash.
                    for name in [sourceRecord.storedName] + sourceRecord.displayAssetNames {
                        try cancellation.check()
                        let destination = sourceDirectory.appendingPathComponent(name)
                        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CanvasImportError.ioFailure }
                        try FileManager.default.copyItem(at: prepared.staged.directoryURL.appendingPathComponent(name), to: destination)
                    }
                    try CanvasImportedContent.validateSource(sourceRecord, notebookDirectory: directory)
                    try JSONEncoder().encode(sourceRecord).write(to: sourceDirectory.appendingPathComponent("\(sourceRecord.id.uuidString).json"), options: .atomic)
                    for (entry, page) in zip(plan.newPages, pages) {
                        try cancellation.check()
                        try CanvasImportedContent.validateBackground(entry.background, notebookDirectory: directory)
                        let url = Self.pageURL(entry.id, notebookID: notebookID, in: directoryURL)
                        guard !FileManager.default.fileExists(atPath: url.path) else { throw CanvasImportError.ioFailure }
                        try JSONEncoder().encode(page).write(to: url, options: .atomic)
                        _ = try CanvasPageStore.decodeAndValidatePage(from: Data(contentsOf: url))
                    }
                    try cancellation.check()
                    try Self.writeLibrary(library, in: directoryURL, allowMissingIndex: allowMissing)
                    continuation.resume(returning: .success(()))
                } catch { continuation.resume(returning: .failure(error)) }
            }
            }
        } onCancel: { cancellation.cancel() }
        try result.get()
        // No cancellation check after this commit point. A published import is success.
        libraryRevision = library.revision
        hasPublishedIndex = true
        if let existingIndex {
            notebooks[existingIndex].pageIDs = notebook.pageIDs
            notebooks[existingIndex].sources = notebook.sources
        } else { notebooks.append(notebook) }
        if pageStores[notebookID] != nil {
            for (entry, page) in zip(plan.newPages, pages) {
                pageStores[notebookID]?[entry.id] = CanvasPageStore(page: page,
                    fileURL: Self.pageURL(entry.id, notebookID: notebookID, in: directoryURL), saveQueue: storageQueue)
            }
        }
        errorMessage = nil
        return CanvasImportPublication(notebookID: notebookID, importedPageCount: plan.newPages.count,
                                       omittedPageCount: plan.omittedPageCount)
    }

    func importedBackgroundBytes(notebookID: UUID, page: CanvasPageData, sourceCache: CanvasExportSourceCache? = nil) async throws -> CanvasImmutableBackground? {
        guard let background = page.importedBackground else { return nil }
        guard let directoryURL,
              let source = notebooks.first(where: { $0.id == notebookID })?.sources.first(where: { $0.id == background.sourceID }) else {
            throw CanvasImportError.ioFailure
        }
        return try await CanvasImportedRenderCache.shared.immutableBytes(background, source: source,
            notebookDirectory: Self.notebookURL(notebookID, in: directoryURL), sourceCache: sourceCache)
    }

    func containsFolder(_ id: CanvasFolderID) -> Bool {
        id == .unfiled || folders.contains { $0.folderID == id }
    }

    func folderName(for id: CanvasFolderID) -> String {
        id == .unfiled ? "Unfiled" : folders.first { $0.folderID == id }?.name ?? "Folder unavailable"
    }

    func notebooks(in folderID: CanvasFolderID) -> [CanvasNotebook] {
        notebooks.filter { $0.folderID == folderID }
    }

    /// Validate both the form and queued request against the current folder names.
    func folderNameError(_ proposedName: String) -> String? {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a folder name." }
        if name.contains(where: { $0.isNewline }) { return "Use one line for the folder name." }
        if name.compare("Unfiled", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return "Unfiled is the built-in folder. Use a different name."
        }
        if folders.contains(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) { return "A folder with this name already exists." }
        return nil
    }

    func createFolder(name: String) async -> CanvasFolder? {
        guard storageIsValid, !isLoading else { return nil }
        await acquireIndexMutation()
        defer { releaseIndexMutation() }
        if let error = folderNameError(name) {
            errorMessage = error
            return nil
        }
        let folder = CanvasFolder(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        let library = CanvasNotebookLibrary(notebooks: notebooks, folders: folders + [folder],
                                            revision: libraryRevision + 1, trash: trash)
        guard await saveMembership(library) else { return nil }
        folders.append(folder)
        return folder
    }

    /// Save a sidebar color through the same FIFO permit as folder and Trash changes.
    func setFolderColor(_ color: CanvasFolderColor, for folderID: UUID) async -> Bool {
        guard storageIsValid, !isLoading else { return false }
        await acquireIndexMutation()
        defer { releaseIndexMutation() }
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            errorMessage = "The folder could not be found. Saved files are preserved."
            return false
        }
        guard folders[index].color != color else { return true }
        var updatedFolders = folders
        updatedFolders[index].color = color
        let library = CanvasNotebookLibrary(notebooks: notebooks, folders: updatedFolders,
                                            revision: libraryRevision + 1, trash: trash)
        guard await saveMembership(library) else { return false }
        folders[index].color = color
        return true
    }

    /// Change only membership. Notebook directories and editable pages stay in place.
    func moveNotebook(_ notebookID: UUID, to folderID: CanvasFolderID) async -> Bool {
        guard storageIsValid, !isLoading else { return false }
        await acquireIndexMutation()
        defer { releaseIndexMutation() }
        guard containsFolder(folderID), let index = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            errorMessage = "The notebook or folder could not be found. Saved files are preserved."
            return false
        }
        guard notebooks[index].folderID != folderID else { return true }
        var updatedNotebooks = notebooks
        updatedNotebooks[index].folderID = folderID
        let library = CanvasNotebookLibrary(notebooks: updatedNotebooks, folders: folders,
                                            revision: libraryRevision + 1, trash: trash)
        guard await saveMembership(library) else { return false }
        // Keep any cover revision that changed while the index write was queued.
        notebooks[index].folderID = folderID
        return true
    }

    /// Call only while holding the FIFO index permit, with a fresh library snapshot.
    private func saveMembership(_ library: CanvasNotebookLibrary) async -> Bool {
        guard let directoryURL else { return false }
        let allowMissingIndex = !hasPublishedIndex
        let succeeded: Bool = await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    try Self.writeLibrary(library, in: directoryURL, allowMissingIndex: allowMissingIndex)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
        if succeeded {
            libraryRevision = library.revision
            hasPublishedIndex = true
            errorMessage = nil
        } else {
            errorMessage = "The folder change could not be saved. Saved files are preserved. Close and reopen the app before you try again."
        }
        return succeeded
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
        let library = CanvasNotebookLibrary(notebooks: updatedNotebooks, folders: folders, revision: libraryRevision + 1, trash: trash)
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
            libraryRevision = library.revision
            let store = CanvasPageStore(page: page, fileURL: fileURL, saveQueue: storageQueue,
                onSaved: { [weak self] snapshot in
                    guard let self, self.notebooks.first(where: { $0.id == notebookID })?.pageIDs.first == pageID else { return }
                    self.updateCover(notebookID: notebookID, page: snapshot)
                })
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
        let library = CanvasNotebookLibrary(notebooks: updatedNotebooks, folders: folders, revision: libraryRevision + 1, trash: trash)
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
            libraryRevision = library.revision
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
            let backgrounds = notebook.pageIDs.compactMap { cached[$0]?.page.importedBackground }
            let valid: Bool = await withCheckedContinuation { continuation in
                storageQueue.async {
                    do {
                        let directory = Self.notebookURL(id, in: directoryURL)
                        for source in notebook.sources { try CanvasImportedContent.validateSource(source, notebookDirectory: directory) }
                        for background in backgrounds {
                            guard notebook.sources.contains(where: { $0.id == background.sourceID }) else { throw CanvasImportError.ioFailure }
                            try CanvasImportedContent.validateBackground(background, notebookDirectory: directory)
                        }
                        continuation.resume(returning: true)
                    } catch { continuation.resume(returning: false) }
                }
            }
            guard valid, notebooks.first(where: { $0.id == id })?.pageIDs == notebook.pageIDs else {
                errorMessage = "The notebook source is missing, invalid, or changed. Saved content is preserved."
                return nil
            }
            return notebook.pageIDs.compactMap { cached[$0] }
        }
        let result: Result<[CanvasPageData], Error> = await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    let directory = Self.notebookURL(id, in: directoryURL)
                    for source in notebook.sources { try CanvasImportedContent.validateSource(source, notebookDirectory: directory) }
                    let pages = try notebook.pageIDs.map { pageID in
                        let page = try CanvasPageStore.decodeAndValidatePage(from: Data(contentsOf:
                            Self.pageURL(pageID, notebookID: id, in: directoryURL)))
                        if let background = page.importedBackground {
                            guard notebook.sources.contains(where: { $0.id == background.sourceID }) else { throw CanvasImportError.ioFailure }
                            try CanvasImportedContent.validateBackground(background, notebookDirectory: directory)
                        }
                        return page
                    }
                    continuation.resume(returning: .success(pages))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch result {
        case .success(let pages):
            // A Trash mutation can finish while the read is queued. Never cache removed pages.
            guard notebooks.first(where: { $0.id == id })?.pageIDs == notebook.pageIDs else { return nil }
            // An overlapping open request can reuse the first completed stores.
            if let cached = pageStores[id] { return notebook.pageIDs.compactMap { cached[$0] } }
            var stores: [UUID: CanvasPageStore] = [:]
            for (pageID, page) in zip(notebook.pageIDs, pages) {
                stores[pageID] = CanvasPageStore(page: page,
                    fileURL: Self.pageURL(pageID, notebookID: id, in: directoryURL), saveQueue: storageQueue,
                    onSaved: { [weak self] snapshot in
                        guard let self, self.notebooks.first(where: { $0.id == id })?.pageIDs.first == pageID else { return }
                        self.updateCover(notebookID: id, page: snapshot)
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
        guard let directoryURL, notebooks.contains(where: { $0.id == notebookID }) else { return }
        if let previous = coverPages[notebookID],
           previous.inkDrawingData == page.inkDrawingData,
           previous.textBoxes == page.textBoxes, previous.shapes == page.shapes,
           previous.paper == page.paper, previous.importedBackground == page.importedBackground { return }
        coverPages[notebookID] = page
        let request = (coverRequests[notebookID] ?? 0) + 1
        coverRequests[notebookID] = request
        let coverURL = Self.notebookURL(notebookID, in: directoryURL).appendingPathComponent("cover.png")
        // A short quiet period joins several completed saves into one cover request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.coverRequests[notebookID] == request,
                  self.notebooks.contains(where: { $0.id == notebookID }) else { return }
            self.coverQueue.async { [weak self] in
                do {
                    let data = try Self.coverData(for: page, notebookDirectory: Self.notebookURL(notebookID, in: directoryURL))
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

    /// The UI must block editor input while isChangingTrash is true.
    func movePageToTrash(_ pageID: UUID, in notebookID: UUID) async -> Bool {
        await changeTrash {
            guard let index = self.notebooks.firstIndex(where: { $0.id == notebookID }),
                  let position = self.notebooks[index].pageIDs.firstIndex(of: pageID) else { return false }
            guard self.notebooks[index].pageIDs.count > 1 else {
                self.errorMessage = "Keep at least one page in the notebook."
                return false
            }
            guard await self.flushCachedPages([notebookID]) else { return false }
            var library = self.trashSnapshot()
            let record = CanvasTrashRecord(content: .page(CanvasTrashedPage(
                notebookID: notebookID, notebookTitle: library.notebooks[index].title,
                pageID: pageID, position: position)))
            library.notebooks[index].pageIDs.remove(at: position)
            library.trash.append(record)
            guard await self.publishTrash(library) else { return false }
            self.pageStores[notebookID]?[pageID]?.retireForTrash()
            self.pageStores[notebookID]?.removeValue(forKey: pageID)
            self.coverRequests[notebookID, default: 0] += 1
            self.coverPages[notebookID] = nil
            if let first = library.notebooks[index].pageIDs.first,
               let page = self.pageStores[notebookID]?[first]?.page {
                self.updateCover(notebookID: notebookID, page: page)
            }
            return true
        }
    }

    func moveNotebookToTrash(_ notebookID: UUID) async -> Bool {
        await changeTrash {
            guard self.notebooks.contains(where: { $0.id == notebookID }),
                  await self.flushCachedPages([notebookID]) else { return false }
            var library = self.trashSnapshot()
            guard let index = library.notebooks.firstIndex(where: { $0.id == notebookID }) else { return false }
            library.trash.append(CanvasTrashRecord(content: .notebook(library.notebooks.remove(at: index))))
            guard await self.publishTrash(library) else { return false }
            self.retireNotebookCache(notebookID)
            return true
        }
    }

    /// Call only from the native folder confirmation action. Unfiled cannot be deleted.
    func moveFolderToTrash(_ folderID: UUID, confirmed: Bool) async -> Bool {
        guard confirmed else { return false }
        return await changeTrash {
            guard self.folders.contains(where: { $0.id == folderID }) else { return false }
            let ids = self.notebooks(in: .custom(folderID)).map(\.id)
            guard await self.flushCachedPages(ids) else { return false }
            var library = self.trashSnapshot()
            guard let index = library.folders.firstIndex(where: { $0.id == folderID }) else { return false }
            let children = library.notebooks.filter { $0.folderID == .custom(folderID) }
            library.trash.append(CanvasTrashRecord(content: .folder(library.folders.remove(at: index), children)))
            library.notebooks.removeAll { $0.folderID == .custom(folderID) }
            guard await self.publishTrash(library) else { return false }
            ids.forEach(self.retireNotebookCache)
            return true
        }
    }

    func restoreFromTrash(_ recordID: UUID) async -> Bool {
        await changeTrash {
            var library = self.trashSnapshot()
            guard let index = library.trash.firstIndex(where: { $0.id == recordID }),
                  !library.trash[index].deletionPending else { return false }
            let record = library.trash[index]
            switch record.content {
            case .page(let page):
                guard await self.flushCachedPages([page.notebookID]) else { return false }
                guard let notebookIndex = library.notebooks.firstIndex(where: { $0.id == page.notebookID }) else {
                    self.errorMessage = "Restore the notebook first."
                    return false
                }
                guard library.notebooks[notebookIndex].pageIDs.count < CanvasNotebook.maximumPageCount else {
                    self.errorMessage = "The notebook has 300 pages. Move a page to Trash before you restore this page."
                    return false
                }
                library.notebooks[notebookIndex].pageIDs.insert(page.pageID,
                    at: min(page.position, library.notebooks[notebookIndex].pageIDs.count))
            case .notebook(var notebook):
                if !self.containsFolder(notebook.folderID) { notebook.folderID = .unfiled }
                notebook.title = self.restoredNotebookTitle(notebook, in: library.notebooks)
                library.notebooks.append(notebook)
            case .folder(var folder, let children):
                // Preserve the restored group if its old name was used again.
                let original = folder.name
                var suffix = 1
                while library.folders.contains(where: {
                    $0.name.compare(folder.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) {
                    folder.name = "\(original) (Restored \(suffix))"
                    suffix += 1
                }
                library.folders.append(folder)
                for var notebook in children {
                    notebook.title = self.restoredNotebookTitle(notebook, in: library.notebooks)
                    library.notebooks.append(notebook)
                }
            }
            guard record.notebooks.allSatisfy({ $0.pageIDs.count <= CanvasNotebook.maximumPageCount }) else {
                self.errorMessage = "A restored notebook cannot have more than 300 pages."
                return false
            }
            // Validate files before publishing restored membership; never write page contents here.
            guard await self.validateRestoredFiles(record, library: library) else { return false }
            library.trash.remove(at: index)
            guard await self.publishTrash(library) else { return false }
            // Drop the whole cache so a restored page is included on the next open.
            if case .page(let page) = record.content {
                self.retireNotebookCache(page.notebookID)
                _ = await self.openNotebook(page.notebookID)
            }
            return true
        }
    }

    /// Persist a non-restorable state before cleanup. Retry that state after a file error.
    func deletePermanently(_ recordID: UUID, confirmed: Bool) async -> Bool {
        guard confirmed else { return false }
        return await changeTrash {
            guard let record = self.trash.first(where: { $0.id == recordID }) else { return false }
            let notebookIDs = Set(record.notebooks.map(\.id))
            // A page in Trash remains owned by its notebook. Remove it with that notebook.
            let dependentIDs = Set(self.trash.compactMap { other -> UUID? in
                if case .page(let page) = other.content, notebookIDs.contains(page.notebookID) { return other.id }
                return nil
            }).union([recordID])
            var library = self.trashSnapshot()
            // Save exact cleanup paths before page files can disappear. Retry uses this manifest.
            if !record.deletionPending {
                do {
                    let before = try await self.ownedResourceReferences(library)
                    var remaining = library
                    remaining.trash.removeAll { dependentIDs.contains($0.id) }
                    let retained = try await self.ownedResourceReferences(remaining)
                        .union(remaining.trash.flatMap { $0.pendingOwnedResources ?? [] })
                    let cleanup = before.subtracting(retained)
                    for resource in cleanup { try resource.validate() }
                    guard let index = library.trash.firstIndex(where: { $0.id == recordID }) else { return false }
                    library.trash[index].pendingOwnedResources = Array(cleanup)
                } catch {
                    self.errorMessage = "Source references could not be checked. No files were removed."
                    return false
                }
            }
            if record.deletionPending {
                do {
                    var remaining = library
                    remaining.trash.removeAll { dependentIDs.contains($0.id) }
                    let retained = try await self.ownedResourceReferences(remaining)
                        .union(remaining.trash.flatMap { $0.pendingOwnedResources ?? [] })
                    for index in library.trash.indices where dependentIDs.contains(library.trash[index].id) {
                        library.trash[index].pendingOwnedResources = library.trash[index].pendingOwnedResources?
                            .filter { !retained.contains($0) }
                    }
                } catch {
                    self.errorMessage = "Source references could not be checked. Permanent deletion stays pending."
                    return false
                }
            }
            for index in library.trash.indices where dependentIDs.contains(library.trash[index].id) {
                library.trash[index].deletionPending = true
            }
            guard await self.publishTrash(library) else { return false }
            notebookIDs.forEach(self.retireNotebookCache)
            // Covers have a separate queue. Drain it before removing owned cover files.
            await withCheckedContinuation { continuation in
                self.coverQueue.async { continuation.resume() }
            }
            let records = self.trash.filter { dependentIDs.contains($0.id) }
            guard let directoryURL = self.directoryURL else { return false }
            let succeeded: Bool = await withCheckedContinuation { continuation in
                self.storageQueue.async {
                    do {
                        var urls = Set<URL>()
                        for item in records {
                            if case .page(let page) = item.content {
                                urls.insert(Self.pageURL(page.pageID, notebookID: page.notebookID, in: directoryURL))
                            }
                            for notebook in item.notebooks {
                                for pageID in notebook.pageIDs {
                                    urls.insert(Self.pageURL(pageID, notebookID: notebook.id, in: directoryURL))
                                }
                                urls.insert(Self.notebookURL(notebook.id, in: directoryURL).appendingPathComponent("cover.png"))
                            }
                        }
                        for item in records {
                            for resource in item.pendingOwnedResources ?? [] {
                                try resource.validate()
                                let notebookDirectory = Self.notebookURL(resource.notebookID, in: directoryURL)
                                let sources = notebookDirectory.appendingPathComponent("sources", isDirectory: true)
                                // Check every owned ancestor. Do not follow a source-directory link.
                                for parentURL in [directoryURL, notebookDirectory, sources] {
                                    let values = try parentURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                                    guard values.isDirectory == true, values.isSymbolicLink != true else {
                                        throw CanvasNotebookStorageError.invalidLibrary
                                    }
                                }
                                urls.insert(sources.appendingPathComponent(resource.fileName))
                            }
                        }
                        // Never remove a directory, unknown file, or referenced source PDF.
                        for url in urls where FileManager.default.fileExists(atPath: url.path) {
                            var ancestor = url.deletingLastPathComponent()
                            while ancestor.path.hasPrefix(directoryURL.path) {
                                let values = try ancestor.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                                guard values.isDirectory == true, values.isSymbolicLink != true else {
                                    throw CanvasNotebookStorageError.invalidLibrary
                                }
                                if ancestor == directoryURL { break }
                                ancestor.deleteLastPathComponent()
                            }
                            let parent = try url.deletingLastPathComponent().resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                            guard parent.isDirectory == true, parent.isSymbolicLink != true else {
                                throw CanvasNotebookStorageError.invalidLibrary
                            }
                            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                                throw CanvasNotebookStorageError.invalidLibrary
                            }
                            try FileManager.default.removeItem(at: url)
                        }
                        continuation.resume(returning: true)
                    } catch { continuation.resume(returning: false) }
                }
            }
            guard succeeded else {
                self.errorMessage = "Permanent deletion did not finish. Some files may be removed. Use Delete Permanently again to finish."
                return false
            }
            library = self.trashSnapshot()
            library.trash.removeAll { dependentIDs.contains($0.id) }
            do {
                let retained = try await self.ownedResourceReferences(library)
                Self.removeUnusedSourceRecords(from: &library, retained: retained)
            } catch {
                self.errorMessage = "Files were removed, but source records could not be checked. Use Delete Permanently again to finish."
                return false
            }
            guard await self.publishTrash(library) else {
                self.errorMessage = "Files were removed, but Trash could not be updated. Use Delete Permanently again to finish."
                return false
            }
            return true
        }
    }

    private func changeTrash(_ operation: () async -> Bool) async -> Bool {
        guard storageIsValid, !isLoading else { return false }
        await acquireIndexMutation()
        guard pageStores.values.allSatisfy({ stores in
            stores.values.allSatisfy { $0.onCanPrepareForDestructiveChange?() ?? true }
        }) else {
            errorMessage = "Finish writing or the page action. Then try Delete or Restore again."
            releaseIndexMutation()
            return false
        }
        isChangingTrash = true
        defer { isChangingTrash = false; releaseIndexMutation() }
        let succeeded = await operation()
        if !succeeded, errorMessage == nil { errorMessage = "The Trash change could not be completed. Saved files are preserved." }
        return succeeded
    }

    private func trashSnapshot() -> CanvasNotebookLibrary {
        CanvasNotebookLibrary(notebooks: notebooks, folders: folders,
                              revision: libraryRevision + 1, trash: trash)
    }

    private func publishTrash(_ library: CanvasNotebookLibrary) async -> Bool {
        guard await saveMembership(library) else { return false }
        notebooks = library.notebooks
        folders = library.folders
        trash = library.trash
        return true
    }

    private func flushCachedPages(_ notebookIDs: [UUID]) async -> Bool {
        for id in notebookIDs {
            for store in pageStores[id]?.values.map({ $0 }) ?? [] {
                store.finishTextEditing()
                guard await store.saveForClose() else {
                    errorMessage = "The current content could not be saved. Delete was cancelled. Keep the notebook open."
                    return false
                }
            }
        }
        return true
    }

    private func retireNotebookCache(_ id: UUID) {
        pageStores[id]?.values.forEach { $0.retireForTrash() }
        pageStores.removeValue(forKey: id)
        coverRequests[id, default: 0] += 1
        coverPages.removeValue(forKey: id)
    }

    private func restoredNotebookTitle(_ notebook: CanvasNotebook, in existing: [CanvasNotebook]) -> String {
        var title = notebook.title
        var suffix = 1
        while existing.contains(where: {
            $0.folderID == notebook.folderID && $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            title = "\(notebook.title) (Restored \(suffix))"
            suffix += 1
        }
        return title
    }

    private func validateRestoredFiles(_ record: CanvasTrashRecord, library: CanvasNotebookLibrary) async -> Bool {
        guard let directoryURL else { return false }
        let succeeded: Bool = await withCheckedContinuation { continuation in
            storageQueue.async {
                do {
                    var owners = record.notebooks
                    if case .page(let page) = record.content {
                        guard let parent = library.notebooks.first(where: { $0.id == page.notebookID }) else {
                            throw CanvasNotebookStorageError.invalidLibrary
                        }
                        var singlePage = parent
                        singlePage.pageIDs = [page.pageID]
                        owners.append(singlePage)
                    }
                    for notebook in owners {
                        let directory = Self.notebookURL(notebook.id, in: directoryURL)
                        for source in notebook.sources {
                            try CanvasImportedContent.validateSource(source, notebookDirectory: directory)
                            let metadataURL = CanvasImportedContent.sourceDirectory(notebookDirectory: directory)
                                .appendingPathComponent("\(source.id.uuidString).json")
                            let metadata = try JSONDecoder().decode(CanvasImportSource.self, from: Data(contentsOf: metadataURL))
                            guard metadata.id == source.id, metadata.sha256 == source.sha256,
                                  metadata.ownedFileNames == source.ownedFileNames else { throw CanvasImportError.ioFailure }
                        }
                        for pageID in notebook.pageIDs {
                            let page = try CanvasPageStore.decodeAndValidatePage(from: Data(contentsOf:
                                Self.pageURL(pageID, notebookID: notebook.id, in: directoryURL)))
                            if let background = page.importedBackground {
                                guard let source = notebook.sources.first(where: { $0.id == background.sourceID }) else {
                                    throw CanvasImportError.ioFailure
                                }
                                try CanvasImportedContent.validateSource(source, notebookDirectory: directory)
                                try CanvasImportedContent.validateBackground(background, notebookDirectory: directory)
                            }
                        }
                    }
                    continuation.resume(returning: true)
                } catch { continuation.resume(returning: false) }
            }
        }
        if !succeeded { errorMessage = "Saved content is missing or invalid. The item stays in Trash. Files are preserved." }
        return succeeded
    }

    /// Resolve page-owned imports on the storage queue. Pending manifests survive partial cleanup.
    private func ownedResourceReferences(_ library: CanvasNotebookLibrary) async throws -> Set<CanvasOwnedNotebookResource> {
        guard let directoryURL else { throw CanvasNotebookStorageError.invalidLibrary }
        return try await withCheckedThrowingContinuation { continuation in
            storageQueue.async {
                do {
                    let owners = library.notebooks + library.trash.flatMap(\.notebooks)
                    var references = Set(library.trash.flatMap { $0.pendingOwnedResources ?? [] })
                    func addPage(_ pageID: UUID, owner: CanvasNotebook) throws {
                        let page = try CanvasPageStore.decodeAndValidatePage(from: Data(contentsOf:
                            Self.pageURL(pageID, notebookID: owner.id, in: directoryURL)))
                        guard let background = page.importedBackground else { return }
                        guard let source = owner.sources.first(where: { $0.id == background.sourceID }),
                              background.kind != .pdf || source.displayAssetNames.contains(background.displayAssetName) else {
                            throw CanvasNotebookStorageError.invalidLibrary
                        }
                        for name in source.ownedFileNames {
                            let resource = CanvasOwnedNotebookResource(notebookID: owner.id, fileName: name)
                            try resource.validate()
                            references.insert(resource)
                        }
                    }
                    for owner in library.notebooks { for pageID in owner.pageIDs { try addPage(pageID, owner: owner) } }
                    for record in library.trash where !record.deletionPending {
                        for owner in record.notebooks { for pageID in owner.pageIDs { try addPage(pageID, owner: owner) } }
                        if case .page(let page) = record.content {
                            guard let owner = owners.first(where: { $0.id == page.notebookID }) else {
                                throw CanvasNotebookStorageError.invalidLibrary
                            }
                            try addPage(page.pageID, owner: owner)
                        }
                    }
                    continuation.resume(returning: references)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    nonisolated private static func removeUnusedSourceRecords(from library: inout CanvasNotebookLibrary,
                                                              retained: Set<CanvasOwnedNotebookResource>) {
        func trimmed(_ notebook: CanvasNotebook) -> CanvasNotebook {
            var result = notebook
            result.sources.removeAll { !retained.contains(CanvasOwnedNotebookResource(notebookID: notebook.id, fileName: $0.storedName)) }
            return result
        }
        library.notebooks = library.notebooks.map(trimmed)
        for index in library.trash.indices where !library.trash[index].deletionPending {
            switch library.trash[index].content {
            case .page: break
            case .notebook(let notebook): library.trash[index].content = .notebook(trimmed(notebook))
            case .folder(let folder, let children): library.trash[index].content = .folder(folder, children.map(trimmed))
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
            guard existing.revision == library.revision - 1 else {
                throw CanvasNotebookStorageError.staleLibrary
            }
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
    nonisolated private static func coverData(for page: CanvasPageData, notebookDirectory: URL) throws -> Data {
        let background = try page.importedBackground.map { try CanvasImportedContent.render($0, notebookDirectory: notebookDirectory) }
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
            if let background { background.draw(in: CGRect(origin: .zero, size: pageSize)) }
            if background == nil && page.paper != .blank {
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
