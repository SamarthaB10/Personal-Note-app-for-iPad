import SwiftUI

/// The library owns navigation. Notebook creation and saving stay in the store.
struct CanvasLibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CanvasAppearance.defaultsKey) private var appearanceValue = CanvasAppearance.light.rawValue
    @StateObject private var store = CanvasNotebookStore()
    @State private var openedNotebook: CanvasNotebook?
    @State private var openedPages: [CanvasPageStore] = []
    @State private var showsCreate = false
    @State private var isOpening = false

    var body: some View {
        Group {
            if let notebook = openedNotebook {
                CanvasNotebookView(notebook: notebook, pages: openedPages, library: store) {
                    openedNotebook = nil
                    openedPages = []
                }
            } else {
                library
            }
        }
        .tint(.blue)
        .preferredColorScheme((CanvasAppearance(rawValue: appearanceValue) ?? .light).colorScheme)
        .sheet(isPresented: $showsCreate) {
            CanvasCreateNotebookView(store: store) { notebook in
                showsCreate = false
                Task { await open(notebook) }
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
                    sidebar.frame(width: 220)
                    Divider()
                    notebookGrid
                }
            } else {
                VStack(spacing: 0) {
                    folderRow.padding(16)
                    Divider()
                    notebookGrid
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                CanvasLucideIcon(kind: .notebook).foregroundStyle(.blue)
                Text("Notebooks").font(.title2.weight(.semibold))
            }
            .padding(.top, 12)
            .accessibilityAddTraits(.isHeader)
            Text("FOLDERS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            folderRow
            Spacer()
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var folderRow: some View {
        HStack(spacing: 12) {
            CanvasLucideIcon(kind: .folder)
            Text("Unfiled").fontWeight(.semibold)
            Spacer(minLength: 8)
            Text("\(store.notebooks.count)").monospacedDigit()
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color.blue.opacity(0.25))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unfiled, \(store.notebooks.count) notebooks")
        .accessibilityAddTraits(.isSelected)
    }

    private var notebookGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unfiled").font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(store.notebooks.isEmpty ? "Create a notebook to start writing." : "\(store.notebooks.count) notebooks")
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 144, maximum: 184), spacing: 24)],
                              alignment: .leading, spacing: 28) {
                        CanvasCreateNotebookCard { showsCreate = true }
                            .disabled(!store.canCreateNotebook || isOpening)
                        ForEach(store.notebooks) { notebook in
                            Button {
                                Task { await open(notebook) }
                            } label: {
                                CanvasNotebookCardView(notebook: notebook, coverURL: store.coverURL(for: notebook.id))
                            }
                            .buttonStyle(.plain)
                            .disabled(isOpening)
                            .accessibilityLabel("\(notebook.title), \(notebook.pageIDs.count) pages")
                            .accessibilityHint("Open this notebook")
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 28)
                }
            }
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
    let create: () -> Void

    var body: some View {
        Button(action: create) {
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
                Text("Create").font(.headline).frame(minHeight: 44, alignment: .top)
                Text("7 blank pages").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create notebook, seven blank pages")
    }
}
