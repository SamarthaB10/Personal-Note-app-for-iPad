import SwiftUI

struct CanvasCreateNotebookView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CanvasNotebookStore
    let onCreate: (CanvasNotebook) -> Void
    @State private var title = ""
    @State private var isCreating = false
    @FocusState private var titleHasFocus: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Notebook name") {
                    TextField("Name", text: $title)
                        .focused($titleHasFocus)
                        .submitLabel(.done)
                        .onSubmit { create() }
                        .disabled(isCreating)
                        .accessibilityLabel("Notebook name")
                }
                Section {
                    Text("The notebook will open with seven blank pages in Unfiled.")
                        .foregroundStyle(.secondary)
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red).accessibilityLabel("Create error: \(error)")
                    }
                }
            }
            .navigationTitle("Create notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating…" : "Create", action: create)
                        .disabled(isCreating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canCreateNotebook)
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
        .presentationDetents([.medium, .large])
        .task { titleHasFocus = true }
    }

    private func create() {
        guard !isCreating, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isCreating = true
        Task {
            if let notebook = await store.createNotebook(title: title) { onCreate(notebook) }
            isCreating = false
        }
    }
}
