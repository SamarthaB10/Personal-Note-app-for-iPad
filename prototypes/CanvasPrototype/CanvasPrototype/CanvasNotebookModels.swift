import Foundation

enum CanvasFolderID: String, Codable {
    case unfiled
}

struct CanvasNotebook: Codable, Identifiable {
    var id: UUID
    var title: String
    var folderID: CanvasFolderID
    var pageIDs: [UUID]
    var createdAt: Date
    var coverRevision: Int
}

struct CanvasNotebookLibrary: Codable {
    var formatVersion = 1
    var notebooks: [CanvasNotebook] = []

    func validate() throws {
        guard formatVersion == 1,
              Set(notebooks.map(\.id)).count == notebooks.count else {
            throw CanvasNotebookStorageError.invalidLibrary
        }
        for notebook in notebooks {
            guard !notebook.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !notebook.pageIDs.isEmpty,
                  Set(notebook.pageIDs).count == notebook.pageIDs.count,
                  notebook.coverRevision >= 0 else {
                throw CanvasNotebookStorageError.invalidLibrary
            }
        }
    }
}

enum CanvasNotebookStorageError: Error {
    case invalidLibrary
    case missingNotebook
}
