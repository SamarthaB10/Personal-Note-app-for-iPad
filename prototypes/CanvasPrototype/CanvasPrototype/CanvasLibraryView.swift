import SwiftUI

/// The library owns navigation. Notebook creation and saving stay in the store.
struct CanvasLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CanvasAppearance.defaultsKey) private var appearanceValue = CanvasAppearance.light.rawValue
    @StateObject private var store = CanvasNotebookStore()
    @State private var openedNotebook: CanvasNotebook?
    @State private var openedPages: [CanvasPageStore] = []
    @State private var showsCreate = false
    @State private var importDestination: CanvasLibraryImportRequest?
    @State private var importMessage: String?
    @State private var isOpening = false
    @State private var selectedFolderID: CanvasFolderID? = .unfiled
    @State private var showsCreateFolder = false
    @State private var isMoving = false
    @State private var showsTrash = false

    private var visibleNotebooks: [CanvasNotebook] {
        selectedFolderID.map { store.notebooks(in: $0) } ?? []
    }

    var body: some View {
        Group {
            if let notebook = openedNotebook {
                CanvasNotebookView(notebook: notebook, pages: openedPages, library: store) {
                    // Home resolves membership after the editor has saved successfully.
                    selectedFolderID = store.notebooks.first { $0.id == notebook.id }?.folderID ?? .unfiled
                    openedNotebook = nil
                    openedPages = []
                }
            } else {
                library
            }
        }
        .disabled(store.isChangingTrash)
        .sheet(isPresented: $showsTrash) { CanvasTrashView(store: store) }
        .tint(.blue)
        .preferredColorScheme((CanvasAppearance(rawValue: appearanceValue) ?? .light).colorScheme)
        .alert("Import complete", isPresented: Binding(
            get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: { Text(importMessage ?? "") }
        .sheet(isPresented: $showsCreate) {
            CanvasCreateNotebookView(store: store, folderID: selectedFolderID ?? .unfiled) { notebook in
                showsCreate = false
                Task { await open(notebook) }
            }
        }
        .sheet(item: $importDestination) { request in
            CanvasImportFilesView(destination: .newNotebook(folderID: request.folderID),
                                  adapter: store.importAdapter, store: store) { publication in
                importDestination = nil
                importMessage = publication.message
                if let notebook = store.notebooks.first(where: { $0.id == publication.notebookID }) {
                    Task { await open(notebook) }
                }
            }
        }
        .sheet(isPresented: $showsCreateFolder) {
            CanvasCreateFolderView(store: store) { folder in
                selectedFolderID = folder.folderID
                showsCreateFolder = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveLifecycleSnapshots() }
        }
    }

    private var library: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 620 {
                HStack(spacing: 0) {
                    folderList.frame(width: 240)
                    Divider()
                    if selectedFolderID != nil { notebookGrid } else { folderOverview }
                }
            } else if selectedFolderID != nil {
                notebookGrid
            } else {
                VStack(spacing: 0) {
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red).padding(16)
                    }
                    folderList
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay {
            if isOpening {
                ProgressView("Opening notebook…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var folderList: some View {
        VStack(spacing: 0) {
            CanvasFolderListView(store: store, selectedFolderID: selectedFolderID,
                                 onSelect: { selectedFolderID = $0 },
                                 onCreate: { showsCreateFolder = true },
                                 onDeleted: { id in
                                     if selectedFolderID == id { selectedFolderID = nil }
                                 })
            Divider()
            HStack {
                Button { showsTrash = true } label: {
                    CanvasLucideIcon(kind: .trash).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Trash")
                .accessibilityValue("\(store.trash.count) items")
                .accessibilityHint("Open deleted items to restore or delete permanently")
                .help("Trash")
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .disabled(isOpening || isMoving || store.isLoading)
    }

    private var folderOverview: some View {
        VStack(spacing: 16) {
            Text("Folders").font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text("Select a folder to open its notebooks.").foregroundStyle(.secondary)
            if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private var notebookGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Button { selectedFolderID = nil } label: {
                    HStack(spacing: 8) {
                        CanvasLucideIcon(kind: .arrowLeft)
                        Text("Folders")
                    }.frame(minHeight: 44)
                }
                .accessibilityLabel("Return to folder list")
                Text(store.folderName(for: selectedFolderID ?? .unfiled))
                    .font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(visibleNotebooks.isEmpty ? "Create a notebook to start writing." : "\(visibleNotebooks.count) notebooks")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(28)
            if let error = store.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
                    .padding(.horizontal, 28).padding(.bottom, 16)
                    .accessibilityLabel("Library error: \(error)")
            }
            if store.isLoading {
                ProgressView("Opening local notebooks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 144, maximum: 184), spacing: 24, alignment: .top)],
                              alignment: .leading, spacing: 28) {
                        Menu {
                            Button("Create blank notebook") { showsCreate = true }
                            Button("Import from Files") { startLibraryImport() }
                        } label: { CanvasCreateNotebookCard() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Create or Import File")
                        .accessibilityHint("Choose a blank notebook or import from Files")
                        .disabled(!store.canCreateNotebook || isOpening)
                        ForEach(visibleNotebooks) { notebook in
                            VStack(spacing: 0) {
                                Button {
                                    Task { await open(notebook) }
                                } label: {
                                    CanvasNotebookCardView(notebook: notebook, coverURL: store.coverURL(for: notebook.id))
                                }
                                .buttonStyle(.plain)
                                .disabled(isOpening)
                                .accessibilityLabel("\(notebook.title), \(notebook.pageIDs.count) pages")
                                .accessibilityHint("Open this notebook. Touch and hold for notebook actions.")
                                .contextMenu {
                                    Button("Delete Notebook", role: .destructive) { deleteNotebook(notebook) }
                                        .disabled(isMoving || isOpening)
                                    Menu("Move to folder") {
                                        moveMenu(for: notebook)
                                    }
                                    .disabled(isMoving || isOpening)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 28)
                }
            }
        }
    }

    private func startLibraryImport() {
        importDestination = CanvasLibraryImportRequest(folderID: selectedFolderID ?? .unfiled)
    }

    private func deleteNotebook(_ notebook: CanvasNotebook) {
        guard !isMoving, !isOpening else { return }
        isMoving = true
        Task {
            _ = await store.moveNotebookToTrash(notebook.id)
            isMoving = false
        }
    }

    private func moveMenu(for notebook: CanvasNotebook) -> some View {
        Group {
            Button("Unfiled") { move(notebook, to: .unfiled) }
                .disabled(notebook.folderID == .unfiled || isMoving)
            ForEach(store.folders) { folder in
                Button(folder.name) { move(notebook, to: folder.folderID) }
                    .disabled(notebook.folderID == folder.folderID || isMoving)
            }
        }
    }

    private func move(_ notebook: CanvasNotebook, to folderID: CanvasFolderID) {
        guard !isMoving else { return }
        isMoving = true
        Task {
            _ = await store.moveNotebook(notebook.id, to: folderID)
            isMoving = false
        }
    }

    private func open(_ notebook: CanvasNotebook) async {
        guard !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        if let pages = await store.openNotebook(notebook.id), !pages.isEmpty {
            openedPages = pages
            openedNotebook = notebook
        }
    }
}

private struct CanvasCreateNotebookCard: View {
    var body: some View {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color(uiColor: .separator))
                    }
                    .overlay {
                        CanvasLucideIcon(kind: .plus)
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(.blue, in: Circle())
                    }
                    .aspectRatio(0.72, contentMode: .fit)
                Text("Create or Import File").font(.headline).lineLimit(2).multilineTextAlignment(.center)
                    .frame(minHeight: 44, alignment: .top)
                Text("Blank notebook, PDF, or image").font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(minHeight: 32, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        .accessibilityLabel("Create or Import File")
    }
}

private struct CanvasLibraryImportRequest: Identifiable {
    let id = UUID()
    let folderID: CanvasFolderID
}
