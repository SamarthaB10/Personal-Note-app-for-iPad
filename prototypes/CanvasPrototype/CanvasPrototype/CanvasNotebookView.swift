import SwiftUI

/// Page changes wait for a local save before removing the active canvas.
struct CanvasNotebookView: View {
    let notebook: CanvasNotebook
    let pages: [CanvasPageStore]
    @ObservedObject var library: CanvasNotebookStore
    let onClose: () -> Void
    @State private var pageIndex = 0
    @State private var isNavigating = false
    @State private var navigationError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let navigationError {
                Text(navigationError).font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .accessibilityLabel("Save error: \(navigationError)")
            }
            CanvasPrototypeRootView(store: pages[pageIndex], notebookTitle: notebook.title,
                                    pageNumber: pageIndex + 1, pageCount: pages.count,
                                    isNavigating: isNavigating, onBack: close,
                                    onPageChange: changePage)
                .id(notebook.pageIDs[pageIndex])
                .allowsHitTesting(!isNavigating)
        }
        .overlay {
            if isNavigating {
                ProgressView("Saving notebook…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func close() {
        guard !isNavigating else { return }
        isNavigating = true
        pages[pageIndex].finishTextEditing()
        Task {
            if await library.saveNotebook(notebook.id) {
                onClose()
            } else {
                navigationError = library.errorMessage ?? "The notebook could not be saved. Stay on this page and try again."
            }
            isNavigating = false
        }
    }

    private func changePage(_ index: Int) {
        guard pages.indices.contains(index), index != pageIndex, !isNavigating else { return }
        isNavigating = true
        let current = pages[pageIndex]
        current.finishTextEditing()
        Task {
            if await current.saveForClose() {
                current.cancelTextBoxChoice()
                current.clearSelection()
                // Keep the user's tools when moving between notebook pages.
                pages[index].tool = current.tool
                pages[index].color = current.color
                pages[index].inkWidth = current.inkWidth
                pageIndex = index
                navigationError = nil
            } else {
                navigationError = current.saveStatus
            }
            isNavigating = false
        }
    }
}
