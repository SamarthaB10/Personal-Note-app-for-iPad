import SwiftUI

/// Folder selection uses the same native controls at all window sizes.
struct CanvasFolderListView: View {
    @ObservedObject var store: CanvasNotebookStore
    let selectedFolderID: CanvasFolderID?
    let onSelect: (CanvasFolderID) -> Void
    let onCreate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Folders").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                row(.unfiled)
                ForEach(store.folders) { folder in row(folder.folderID) }
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
    }

    private func row(_ id: CanvasFolderID) -> some View {
        Button { onSelect(id) } label: {
            HStack(spacing: 12) {
                CanvasLucideIcon(kind: .folder)
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
        .accessibilityAddTraits(selectedFolderID == id ? [.isSelected] : [])
    }
}
