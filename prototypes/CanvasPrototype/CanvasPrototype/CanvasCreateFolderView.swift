import SwiftUI

struct CanvasCreateFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CanvasNotebookStore
    let onCreate: (CanvasFolder) -> Void
    @State private var name = ""
    @State private var isCreating = false
    @FocusState private var nameHasFocus: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder name") {
                    TextField("Name", text: $name)
                        .focused($nameHasFocus)
                        .submitLabel(.done)
                        .onSubmit { create() }
                        .disabled(isCreating)
                        .accessibilityLabel("Folder name")
                    if !name.isEmpty, let error = store.folderNameError(name) {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Text("A folder contains notebooks. Folders have one level.")
                        .foregroundStyle(.secondary)
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red)
                            .accessibilityLabel("Create folder error: \(error)")
                    }
                }
            }
            .navigationTitle("Create folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating…" : "Create", action: create)
                        .disabled(isCreating || store.isLoading || store.folderNameError(name) != nil || !store.canCreateNotebook)
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
        .presentationDetents([.medium, .large])
        .task { nameHasFocus = true }
    }

    private func create() {
        guard !isCreating, store.folderNameError(name) == nil else { return }
        isCreating = true
        Task {
            if let folder = await store.createFolder(name: name) { onCreate(folder) }
            isCreating = false
        }
    }
}
