import SwiftUI

/// Folder selection uses the same native controls at all window sizes.
struct CanvasFolderListView: View {
    @ObservedObject var store: CanvasNotebookStore
    let selectedFolderID: CanvasFolderID?
    let onSelect: (CanvasFolderID) -> Void
    let onCreate: () -> Void
    let onDeleted: (CanvasFolderID) -> Void
    @State private var folderToDelete: CanvasFolder?
    @State private var folderToColor: CanvasFolder?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Folders").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                row(.unfiled)
                ForEach(store.folders) { folder in
                    row(folder.folderID)
                        .contextMenu {
                            Button("Change color") { folderToColor = folder }
                            Button("Delete", role: .destructive) { folderToDelete = folder }
                        }
                }
                Button(action: onCreate) {
                    HStack(spacing: 12) {
                        CanvasLucideIcon(kind: .plus)
                        Text("Create folder")
                        Spacer()
                    }
                    .frame(minHeight: 48)
                }
                .disabled(!store.canCreateNotebook)
                .accessibilityLabel("Create folder")
            }
            .padding(20)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .sheet(item: $folderToColor) { folder in
            CanvasFolderColorView(store: store, folder: folder)
        }
        .confirmationDialog("Delete folder", isPresented: Binding(
            get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }
        ), titleVisibility: .visible, presenting: folderToDelete) { folder in
            Button("Delete", role: .destructive) {
                folderToDelete = nil
                Task {
                    if await store.moveFolderToTrash(folder.id, confirmed: true) {
                        onDeleted(folder.folderID)
                    }
                }
            }
            Button("Cancel", role: .cancel) { folderToDelete = nil }
        } message: { folder in
            Text("Are you sure? \(folder.name) and its notebooks will move to Trash. You can restore them together.")
        }
    }

    private func row(_ id: CanvasFolderID) -> some View {
        Button { onSelect(id) } label: {
            HStack(spacing: 12) {
                CanvasLucideIcon(kind: .folder)
                    .foregroundStyle(iconColor(for: id))
                Text(store.folderName(for: id)).fontWeight(selectedFolderID == id ? .semibold : .regular)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text("\(store.notebooks(in: id).count)").monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(selectedFolderID == id ? Color.blue.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.folderName(for: id)), \(store.notebooks(in: id).count) notebooks")
        .accessibilityValue(store.folders.first(where: { $0.folderID == id })?.color.title ?? "")
        .accessibilityHint(id == .unfiled ? "Open Unfiled" : "Open this folder. Touch and hold to change its color or delete it.")
        .accessibilityAddTraits(selectedFolderID == id ? [.isSelected] : [])
    }

    private func iconColor(for id: CanvasFolderID) -> Color {
        store.folders.first(where: { $0.folderID == id })
            .map { Color(uiColor: $0.color.uiColor) } ?? .secondary
    }
}
