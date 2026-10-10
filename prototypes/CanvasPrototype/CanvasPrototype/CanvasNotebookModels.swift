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
    var defaultPaper: CanvasPaper = .blank

    static let maximumPageCount = 300

    init(id: UUID, title: String, folderID: CanvasFolderID, pageIDs: [UUID],
         createdAt: Date, coverRevision: Int, defaultPaper: CanvasPaper = .blank) {
        self.id = id
        self.title = title
        self.folderID = folderID
        self.pageIDs = pageIDs
        self.createdAt = createdAt
        self.coverRevision = coverRevision
        self.defaultPaper = defaultPaper
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, folderID, pageIDs, createdAt, coverRevision, defaultPaper
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        folderID = try values.decode(CanvasFolderID.self, forKey: .folderID)
        pageIDs = try values.decode([UUID].self, forKey: .pageIDs)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        coverRevision = try values.decode(Int.self, forKey: .coverRevision)
        defaultPaper = try values.decodeIfPresent(CanvasPaper.self, forKey: .defaultPaper) ?? .blank
    }
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
