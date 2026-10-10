import SwiftUI

/// A named palette keeps color selection accessible without changing writing tools.
struct CanvasFolderColorView: View {
    @ObservedObject var store: CanvasNotebookStore
    let folder: CanvasFolder
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    private var selectedColor: CanvasFolderColor {
        store.folders.first(where: { $0.id == folder.id })?.color ?? folder.color
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(folder.name).font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red)
                            .accessibilityLabel("Folder color error: \(error)")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 16) {
                        ForEach(CanvasFolderColor.allCases) { color in
                            Button {
                                guard !isSaving else { return }
                                isSaving = true
                                Task {
                                    if await store.setFolderColor(color, for: folder.id) { dismiss() }
                                    isSaving = false
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Circle().fill(Color(uiColor: color.uiColor))
                                        .frame(width: 36, height: 36)
                                    Text(color.title).font(.subheadline)
                                    Text(selectedColor == color ? "Selected" : " ")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 100)
                                .background(Color(uiColor: .secondarySystemBackground),
                                            in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(color.title)
                            .accessibilityAddTraits(selectedColor == color ? [.isSelected] : [])
                        }
                    }
                }.padding(24)
            }
            .navigationTitle("Folder color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .disabled(isSaving || store.isChangingTrash)
            .interactiveDismissDisabled(isSaving)
        }
        .presentationDetents([.medium, .large])
    }
}
