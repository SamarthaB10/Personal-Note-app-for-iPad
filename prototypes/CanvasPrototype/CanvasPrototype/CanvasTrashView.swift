import SwiftUI

struct CanvasTrashView: View {
    @ObservedObject var store: CanvasNotebookStore
    @Environment(\.dismiss) private var dismiss
    @State private var permanentDeleteID: UUID?

    var body: some View {
        NavigationStack {
            List {
                if let error = store.undoHistory.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityLabel("Undo error: \(error)")
                }
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityLabel("Trash error: \(error)")
                }
                if store.trash.isEmpty { Text("Trash is empty.").foregroundStyle(.secondary) }
                ForEach(store.trash) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.title).font(.headline)
                        Text(record.deletedAt, style: .date).foregroundStyle(.secondary)
                        if record.deletionPending {
                            Text("Permanent deletion must finish. This item cannot be restored.")
                                .font(.callout).foregroundStyle(.red)
                        }
                        HStack {
                            Button("Restore") { Task { _ = await store.restoreFromTrash(record.id) } }
                                .disabled(record.deletionPending)
                            Spacer()
                            Button("Delete Permanently", role: .destructive) { permanentDeleteID = record.id }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Trash")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await store.undoHistory.undo() } } label: { CanvasLucideIcon(kind: .undo) }
                        .disabled(store.undoHistory.count == 0 || store.undoHistory.isUndoing)
                        .accessibilityLabel("Undo, \(store.undoHistory.count) of 7 steps available")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .disabled(store.isChangingTrash || store.undoHistory.isUndoing)
            .confirmationDialog("Delete this item permanently?", isPresented: Binding(
                get: { permanentDeleteID != nil }, set: { if !$0 { permanentDeleteID = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Permanently", role: .destructive) {
                    guard let id = permanentDeleteID else { return }
                    permanentDeleteID = nil
                    Task { _ = await store.deletePermanently(id, confirmed: true) }
                }
                Button("Cancel", role: .cancel) { permanentDeleteID = nil }
            } message: { Text("The item and its saved content will be removed. You cannot undo this action.") }
        }
    }
}
