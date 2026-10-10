import Foundation

struct CanvasTrashedPage: Codable {
    var notebookID: UUID
    var notebookTitle: String
    var pageID: UUID
    var position: Int
}

struct CanvasTrashRecord: Codable, Identifiable {
    enum Content: Codable {
        case page(CanvasTrashedPage)
        case notebook(CanvasNotebook)
        case folder(CanvasFolder, [CanvasNotebook])
    }
    var id = UUID()
    var deletedAt = Date()
    var content: Content
    // Persist before removing any files. A failed cleanup can be retried after reopen.
    var deletionPending = false
    var pendingOwnedResources: [CanvasOwnedNotebookResource]? = nil

    var notebooks: [CanvasNotebook] {
        switch content {
        case .page: return []
        case .notebook(let notebook): return [notebook]
        case .folder(_, let notebooks): return notebooks
        }
    }
    var title: String {
        switch content {
        case .page(let page): return "Page \(page.position + 1) — \(page.notebookTitle)"
        case .notebook(let notebook): return notebook.title
        case .folder(let folder, _): return folder.name
        }
    }
}

extension CanvasNotebookLibrary {
    func validateTrash() throws {
        guard Set(trash.map(\.id)).count == trash.count else {
            throw CanvasNotebookStorageError.invalidLibrary
        }
        let allNotebooks = notebooks + trash.flatMap(\.notebooks)
        guard Set(allNotebooks.map(\.id)).count == allNotebooks.count else {
            throw CanvasNotebookStorageError.invalidLibrary
        }
        var pages = Set<String>()
        for notebook in allNotebooks {
            guard !notebook.pageIDs.isEmpty,
                  !notebook.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  notebook.coverRevision >= 0,
                  Set(notebook.sources.map(\.id)).count == notebook.sources.count,
                  notebook.sources.allSatisfy({ $0.storedName == "\($0.id.uuidString).source" && $0.byteCount > 0 && $0.sha256.count == 64 }) else { throw CanvasNotebookStorageError.invalidLibrary }
            for source in notebook.sources {
                for name in source.ownedFileNames { try CanvasOwnedNotebookResource(notebookID: notebook.id, fileName: name).validate() }
            }
            for pageID in notebook.pageIDs {
                guard pages.insert("\(notebook.id)/\(pageID)").inserted else {
                    throw CanvasNotebookStorageError.invalidLibrary
                }
            }
        }
        var folderIDs = Set(folders.map(\.id))
        for record in trash {
            for resource in record.pendingOwnedResources ?? [] { try resource.validate() }
            guard record.deletionPending || record.pendingOwnedResources == nil else {
                throw CanvasNotebookStorageError.invalidLibrary
            }
            switch record.content {
            case .page(let page):
                guard page.position >= 0,
                      allNotebooks.contains(where: { $0.id == page.notebookID }),
                      pages.insert("\(page.notebookID)/\(page.pageID)").inserted else {
                    throw CanvasNotebookStorageError.invalidLibrary
                }
            case .notebook: break
            case .folder(let folder, let children):
                guard folderIDs.insert(folder.id).inserted, !folder.name.isEmpty,
                      children.allSatisfy({ $0.folderID == folder.folderID }) else {
                    throw CanvasNotebookStorageError.invalidLibrary
                }
            }
        }
    }
}

/// An app-owned file under the owner's notebook directory: sources/<fileName>.
/// Issue 9 maps its source records to this type. A user file URL is never accepted.
struct CanvasOwnedNotebookResource: Codable, Hashable {
    var notebookID: UUID
    var fileName: String

    func validate() throws {
        guard !fileName.isEmpty, fileName != ".", fileName != "..",
              !fileName.contains("/"), !fileName.contains("\\"),
              !fileName.contains("\0") else { throw CanvasNotebookStorageError.invalidLibrary }
    }
}
