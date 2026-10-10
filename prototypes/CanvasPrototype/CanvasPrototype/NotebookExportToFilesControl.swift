import SwiftUI
import UIKit

enum NotebookExportScope: Sendable { case currentPage, completeNotebook }

/// The host captures content at the time of the tap, including the active text editor.
/// Put this control beside the import worker's explicit Import from Files button.
@MainActor
struct NotebookExportToFilesControl: View {
    let captureSnapshot: @MainActor (NotebookExportScope) async throws -> ExportNotebookSnapshot
    private let exporter = NotebookPDFExporter()
    @State private var rendering = false
    @State private var artifact: ExportPDFArtifact?
    @State private var temporaryCopy: ExportPDFArtifact?
    @State private var isVisible = true
    @State private var message: String?
    @State private var failure: String?
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Button("Current page") { start(.currentPage) }
                Button("Complete notebook") { start(.completeNotebook) }
            } label: {
                Text(rendering ? "Preparing PDF…" : "Export to Files")
                    .frame(minHeight: 44)
            }
            .disabled(rendering || artifact != nil)
            .accessibilityHint("Save the current page or complete notebook as a PDF.")
            if let message {
                Text(message).font(.caption).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; exportTask?.cancel() }
        .sheet(item: $artifact, onDismiss: pickerDismissed) { item in
            NotebookFilesExportPicker(url: item.url) { saved in
                message = saved ? "PDF saved to Files." : "Export cancelled."
                pickerDismissed()
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "The PDF could not be exported.")
        }
    }

    private func start(_ scope: NotebookExportScope) {
        guard !rendering, artifact == nil else { return }
        rendering = true
        message = "Preparing PDF. You can continue to write."
        exportTask = Task {
            do {
                let snapshot = try await captureSnapshot(scope)
                try Task.checkCancellation()
                let result = try await exporter.export(snapshot)
                guard isVisible, !Task.isCancelled else {
                    try await exporter.removeTemporaryCopy(result)
                    rendering = false
                    exportTask = nil
                    return
                }
                temporaryCopy = result
                artifact = result
                message = "Choose a destination in Files."
            } catch is CancellationError {
                message = "Export cancelled."
            } catch {
                if isVisible { failure = error.localizedDescription }
                message = nil
            }
            rendering = false
            exportTask = nil
        }
    }

    private func pickerDismissed() {
        if message == "Choose a destination in Files." { message = "Export cancelled." }
        let copy = temporaryCopy
        artifact = nil
        temporaryCopy = nil
        if let copy {
            Task {
                do { try await exporter.removeTemporaryCopy(copy) }
                catch { failure = "The temporary PDF could not be removed. The saved copy is unchanged." }
            }
        }
    }
}

/// Native Save to Files. asCopy protects the app's temporary PDF during delivery.
@MainActor
private struct NotebookFilesExportPicker: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Bool) -> Void
        private var finished = false
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(!urls.isEmpty)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }
        private func finish(_ saved: Bool) {
            guard !finished else { return }
            finished = true
            completion(saved)
        }
    }
}
