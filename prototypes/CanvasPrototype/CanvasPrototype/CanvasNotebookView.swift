import SwiftUI

/// The library keeps stable page stores. Scrolling changes only the active controls.
struct CanvasNotebookView: View {
    let notebook: CanvasNotebook
    let pages: [CanvasPageStore]
    @ObservedObject var library: CanvasNotebookStore
    let onClose: () -> Void
    @State private var pageIndex = 0
    @State private var importRequest: CanvasNotebookImportRequest?
    @State private var importMessage: String?
    @State private var isNavigating = false
    @State private var isAddingPage = false
    @State private var isChangingPaper = false
    @State private var isMovingNotebook = false
    @State private var navigationError: String?
    @State private var scrollRequest: CanvasNotebookScrollRequest?
    @State private var zoomPercent = 100
    @AppStorage(CanvasAppearance.defaultsKey) private var appearanceValue = CanvasAppearance.light.rawValue

    private var currentNotebook: CanvasNotebook {
        library.notebooks.first { $0.id == notebook.id } ?? notebook
    }

    private var orderedPages: [CanvasNotebookPage] {
        currentNotebook.pageIDs.compactMap { id in
            let store = library.pageStore(notebookID: notebook.id, pageID: id)
                ?? zip(notebook.pageIDs, pages).first(where: { $0.0 == id })?.1
            return store.map { CanvasNotebookPage(id: id, store: $0) }
        }
    }

    private var appearance: CanvasAppearance { CanvasAppearance(rawValue: appearanceValue) ?? .light }

    var body: some View {
        let entries = orderedPages
        VStack(spacing: 0) {
            HStack {
                Text(library.folderName(for: currentNotebook.folderID)).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button("Unfiled") { moveNotebook(to: .unfiled) }
                        .disabled(currentNotebook.folderID == .unfiled)
                    ForEach(library.folders) { folder in
                        Button(folder.name) { moveNotebook(to: folder.folderID) }
                            .disabled(currentNotebook.folderID == folder.folderID)
                    }
                } label: {
                    HStack(spacing: 8) {
                        CanvasLucideIcon(kind: .folder)
                        Text(isMovingNotebook ? "Moving…" : "Move notebook")
                    }.frame(minHeight: 44)
                }
                .disabled(isMovingNotebook || isNavigating || isAddingPage || isChangingPaper)
                .accessibilityLabel("Move notebook to folder")
            }
            .padding(.horizontal, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            if let importMessage { Text(importMessage).font(.callout).padding(12) }
            if let navigationError {
                Text(navigationError).font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .accessibilityLabel("Notebook error: \(navigationError)")
            }
            if !entries.isEmpty {
                let activeIndex = min(pageIndex, entries.count - 1)
                CanvasPrototypeRootView(
                    store: entries[activeIndex].store, pages: entries,
                    notebookTitle: currentNotebook.title,
                    pageNumber: activeIndex + 1, pageCount: currentNotebook.pageIDs.count,
                    defaultPaper: currentNotebook.defaultPaper,
                    isNavigating: isNavigating, isAddingPage: isAddingPage,
                    isChangingPaper: isChangingPaper,
                    appearance: appearance, zoomPercent: zoomPercent,
                    scrollRequest: scrollRequest,
                    onBack: close, onPageChange: requestPage,
                    onVisiblePageChange: setVisiblePage,
                    onZoomChange: { zoomPercent = $0 }, onAddPage: addPage,
                    onAddPageAfterCurrent: addPageAfterCurrent,
                    onImportPDF: startPDFImport,
                    onDefaultPaperChange: setDefaultPaper,
                    onAppearanceChange: { appearanceValue = $0.rawValue }
                )
                .allowsHitTesting(!isNavigating)
            } else {
                Text("The notebook pages are unavailable. Saved files are preserved.")
                    .padding()
            }
        }
        .sheet(item: $importRequest) { request in
            CanvasImportFilesView(destination: .insertPDF(notebookID: notebook.id, afterPageID: request.pageID),
                                  adapter: library.importAdapter, store: library) { publication in
                importMessage = publication.message
                importRequest = nil
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .onChange(of: appearance, initial: true) { _, value in
            CanvasToolSettings.shared.applyAppearance(value)
        }
        .overlay {
            if isNavigating {
                ProgressView("Saving notebook…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func startPDFImport() {
        let entries = orderedPages
        guard entries.indices.contains(pageIndex), !isNavigating, !isAddingPage,
              currentNotebook.pageIDs.count < CanvasNotebook.maximumPageCount else { return }
        // Capture the stable page ID before the Files sheet opens.
        importRequest = CanvasNotebookImportRequest(pageID: entries[pageIndex].id)
    }

    private func moveNotebook(to folderID: CanvasFolderID) {
        guard !isMovingNotebook, !isNavigating, !isAddingPage, !isChangingPaper else { return }
        isMovingNotebook = true
        Task {
            if await library.moveNotebook(notebook.id, to: folderID) {
                navigationError = nil
            } else {
                navigationError = library.errorMessage ?? "The notebook could not be moved. Saved files are preserved."
            }
            isMovingNotebook = false
        }
    }

    private func close() {
        guard !isNavigating, !isAddingPage, !isChangingPaper, !isMovingNotebook else { return }
        isNavigating = true
        orderedPages.forEach { $0.store.finishTextEditing() }
        Task {
            if await library.saveNotebook(notebook.id) {
                onClose()
            } else {
                navigationError = library.errorMessage ?? "The notebook could not be saved. Keep it open and try again."
            }
            isNavigating = false
        }
    }

    private func requestPage(_ index: Int) {
        let entries = orderedPages
        guard entries.indices.contains(index), !isNavigating else { return }
        scrollRequest = CanvasNotebookScrollRequest(pageID: entries[index].id)
    }

    private func setVisiblePage(_ index: Int) {
        let entries = orderedPages
        guard entries.indices.contains(index), pageIndex != index else { return }
        if entries.indices.contains(pageIndex) {
            entries[pageIndex].store.finishTextEditing()
            entries[pageIndex].store.cancelTextBoxChoice()
        }
        pageIndex = index
    }

    private func addPage() {
        addPage(after: nil)
    }

    private func addPageAfterCurrent() {
        let entries = orderedPages
        guard entries.indices.contains(pageIndex) else { return }
        addPage(after: entries[pageIndex].id)
    }

    private func addPage(after anchorPageID: UUID?) {
        guard !isAddingPage, !isNavigating, !isChangingPaper,
              currentNotebook.pageIDs.count < CanvasNotebook.maximumPageCount else { return }
        isAddingPage = true
        Task {
            let newStore: CanvasPageStore?
            if let anchorPageID {
                newStore = await library.insertPage(after: anchorPageID, in: notebook.id)
            } else {
                newStore = await library.appendPage(to: notebook.id)
            }
            if let newStore,
               let newPage = orderedPages.first(where: { $0.store === newStore }) {
                navigationError = nil
                scrollRequest = CanvasNotebookScrollRequest(pageID: newPage.id)
            } else {
                navigationError = library.errorMessage ?? "The page could not be added. Saved pages are preserved."
            }
            isAddingPage = false
        }
    }

    private func setDefaultPaper(_ paper: CanvasPaper) {
        guard !isChangingPaper, !isAddingPage, !isNavigating else { return }
        isChangingPaper = true
        Task {
            if await library.setDefaultPaper(paper, for: notebook.id) {
                navigationError = nil
            } else {
                navigationError = library.errorMessage ?? "The default paper could not be saved. Try again."
            }
            isChangingPaper = false
        }
    }
}

private struct CanvasNotebookImportRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
}
