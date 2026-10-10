import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The library presents `.newNotebook`. The notebook plus menu presents `.insertPDF`.
/// Use page IDs as anchors. Never keep a stale numeric insertion index across awaits.
enum CanvasImportDestination: Sendable {
    case newNotebook(folderID: CanvasFolderID)
    case insertPDF(notebookID: UUID, afterPageID: UUID)

    var allowsImages: Bool {
        if case .newNotebook = self { return true }
        return false
    }
}

/// The store owns publication. This view never writes its index.
/// The store must recheck capacity under its index mutation permit and return actual counts.
struct CanvasImportPublication: Sendable {
    let notebookID: UUID
    let importedPageCount: Int
    let omittedPageCount: Int
    var message: String {
        omittedPageCount == 0 ? "Imported \(importedPageCount) pages." :
            "Imported \(importedPageCount) pages. \(omittedPageCount) pages did not fit within the 300-page limit. The complete source file is kept."
    }
}

@MainActor
protocol CanvasImportPublishing: AnyObject {
    func existingPageCount(for destination: CanvasImportDestination) throws -> Int
    func publishImport(_ prepared: CanvasPreparedImport, to destination: CanvasImportDestination,
                       title: String) async throws -> CanvasImportPublication
}

/// Present from Create or Import File -> Import from Files, or plus -> Import PDF.
/// No notebook is published until the store completes publishImport successfully.
struct CanvasImportFilesView: View {
    let destination: CanvasImportDestination
    let adapter: CanvasImportAdapter
    let store: any CanvasImportPublishing
    let onPublished: (CanvasImportPublication) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsPicker = false
    @State private var staged: CanvasStagedImport?
    @State private var pendingURLs: [URL] = []
    @State private var password = ""
    @State private var needsPassword = false
    @State private var title = ""
    @State private var message: String?
    @State private var isWorking = false
    @State private var work: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                if case .newNotebook = destination {
                    TextField("Notebook title", text: $title)
                }
                Button("Import from Files") { showsPicker = true }
                    .disabled(isWorking || staged != nil)
                if needsPassword {
                    SecureField("PDF password", text: $password)
                    Button("Unlock and Import") { beginImport() }.disabled(isWorking)
                }
                if isWorking { ProgressView("Importing file…") }
                if let message { Text(message).accessibilityLabel(message) }
            }
            .navigationTitle(destination.allowsImages ? "Create or Import File" : "Import PDF")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        work?.cancel()
                        if !isWorking { abandon() }
                    }
                }
            }
            .interactiveDismissDisabled(isWorking || staged != nil)
            .sheet(isPresented: $showsPicker) {
                CanvasNativeFilesPicker(allowsImages: destination.allowsImages) { urls in
                    showsPicker = false
                    pendingURLs = urls
                    if !urls.isEmpty { beginImport() }
                }
            }
        }
    }

    private func beginImport() {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        work = Task { @MainActor in
            defer { isWorking = false; work = nil; password = "" }
            do {
                // One selected PDF or image becomes one notebook.
                if staged == nil, let url = pendingURLs.first {
                    staged = try await adapter.stage(url)
                    pendingURLs = []
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = url.deletingPathExtension().lastPathComponent
                    }
                }
                try Task.checkCancellation()
                guard let staged else { return }
                let count = try store.existingPageCount(for: destination)
                let prepared = try await adapter.prepare(staged, existingPageCount: count,
                    password: needsPassword ? password : nil)
                try Task.checkCancellation()
                // Publication has a commit point: the store must not throw cancellation after it.
                let publication = try await store.publishImport(prepared, to: destination, title: title)
                self.staged = nil
                needsPassword = false
                // Cleanup failure cannot turn a successful publication into a failed import.
                try? await adapter.discard(staged)
                onPublished(publication)
                dismiss()
            } catch CanvasImportError.passwordRequired {
                needsPassword = true
                message = CanvasImportError.passwordRequired.localizedDescription
            } catch CanvasImportError.incorrectPassword {
                needsPassword = true
                message = CanvasImportError.incorrectPassword.localizedDescription
            } catch is CancellationError {
                if let staged { try? await adapter.discard(staged) }
                staged = nil
                dismiss()
            } catch {
                message = (error as? CanvasImportError)?.localizedDescription ??
                    "The import failed. Existing notebooks and the source file are unchanged."
                // Allow a new selection after a non-password failure.
                if let staged { try? await adapter.discard(staged) }
                staged = nil
                needsPassword = false
            }
        }
    }

    private func abandon() {
        let abandoned = staged
        staged = nil
        password = ""
        Task {
            if let abandoned { try? await adapter.discard(abandoned) }
        }
        dismiss()
    }
}

/// Open mode preserves the user's file. The adapter holds its security scope while copying.
struct CanvasNativeFilesPicker: UIViewControllerRepresentable {
    let allowsImages: Bool
    let completion: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = allowsImages ? [.pdf, .image] : [.pdf]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            controller.dismiss(animated: true)
            completion(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true)
            completion([])
        }
    }
}
