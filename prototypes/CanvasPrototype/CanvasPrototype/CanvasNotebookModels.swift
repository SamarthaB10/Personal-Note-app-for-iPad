import Foundation

enum CanvasFolderID: Codable, Hashable, Sendable {
    case unfiled
    case custom(UUID)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if value == "unfiled" {
            self = .unfiled
        } else if let id = UUID(uuidString: value) {
            self = .custom(id)
        } else {
            throw CanvasNotebookStorageError.invalidLibrary
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .unfiled: try value.encode("unfiled")
        case .custom(let id): try value.encode(id.uuidString)
        }
    }
}

struct CanvasFolder: Codable, Identifiable {
    var id: UUID
    var name: String
    var folderID: CanvasFolderID { .custom(id) }
}

struct CanvasNotebook: Codable, Identifiable {
    var id: UUID
    var title: String
    var folderID: CanvasFolderID
    var pageIDs: [UUID]
    var createdAt: Date
    var coverRevision: Int
    var sources: [CanvasImportSource] = []
    var defaultPaper: CanvasPaper = .blank

    static let maximumPageCount = 300

    init(id: UUID, title: String, folderID: CanvasFolderID, pageIDs: [UUID],
         createdAt: Date, coverRevision: Int, defaultPaper: CanvasPaper = .blank, sources: [CanvasImportSource] = []) {
        self.id = id
        self.title = title
        self.folderID = folderID
        self.pageIDs = pageIDs
        self.createdAt = createdAt
        self.coverRevision = coverRevision
        self.defaultPaper = defaultPaper
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, folderID, pageIDs, createdAt, coverRevision, defaultPaper, sources
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
        sources = try values.decodeIfPresent([CanvasImportSource].self, forKey: .sources) ?? []
    }
}

struct CanvasNotebookLibrary: Codable {
    var formatVersion = 1
    var notebooks: [CanvasNotebook] = []
    var folders: [CanvasFolder] = []
    var revision = 0
    var trash: [CanvasTrashRecord] = []

    init(notebooks: [CanvasNotebook] = [], folders: [CanvasFolder] = [], revision: Int = 0, trash: [CanvasTrashRecord] = []) {
        self.notebooks = notebooks
        self.folders = folders
        self.revision = revision
        self.trash = trash
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, notebooks, folders, revision, trash }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        notebooks = try values.decode([CanvasNotebook].self, forKey: .notebooks)
        // The issue 3 and issue 4 indexes have no folder list or revision.
        folders = try values.decodeIfPresent([CanvasFolder].self, forKey: .folders) ?? []
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        trash = try values.decodeIfPresent([CanvasTrashRecord].self, forKey: .trash) ?? []
    }

    func validate() throws {
        guard formatVersion == 1, revision >= 0, revision < Int.max,
              Set(folders.map(\.id)).count == folders.count,
              Set(notebooks.map(\.id)).count == notebooks.count else {
            throw CanvasNotebookStorageError.invalidLibrary
        }
        try validateTrash()
        for folder in folders {
            guard !folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CanvasNotebookStorageError.invalidLibrary
            }
        }
        let folderIDs = Set(folders.map(\.folderID)).union([.unfiled])
        for notebook in notebooks {
            guard folderIDs.contains(notebook.folderID),
                  !notebook.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !notebook.pageIDs.isEmpty,
                  Set(notebook.sources.map(\.id)).count == notebook.sources.count,
                  notebook.sources.allSatisfy({ $0.storedName == "\($0.id.uuidString).source" && $0.displayAssetNames.allSatisfy({ !$0.contains("/") && !$0.contains("..") && $0.hasSuffix(".pdf") }) && $0.byteCount > 0 && $0.sha256.count == 64 && $0.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) }),
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
    case staleLibrary
}
