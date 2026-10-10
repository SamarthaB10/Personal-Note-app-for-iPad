import SwiftUI

struct CanvasSelectionActionsView: View {
    @ObservedObject var store: CanvasPageStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selection").font(.headline).accessibilityAddTraits(.isHeader)
            Text(store.selectionSummary).font(.footnote).foregroundStyle(.secondary)
            Text("Drag inside the selection to move it. Drag the round handle to resize it.")
                .font(.footnote).foregroundStyle(.secondary)
            if let box = store.selectedTextBox {
                DisclosureGroup("Text format") {
                    ScrollView(.vertical) {
                        CanvasTextFormatView(store: store, boxID: box.id)
                    }
                    .frame(maxHeight: 240)
                }
                Button("Edit text box") {
                    store.editSelectedTextBox()
                    onDismiss()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(!store.canWrite)
                .accessibilityHint("Open the keyboard for this text box only")
                Divider()
            }
            Text("Move").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                moveButton("Left", x: -12, y: 0)
                moveButton("Right", x: 12, y: 0)
            }
            HStack(spacing: 8) {
                moveButton("Up", x: 0, y: -12)
                moveButton("Down", x: 0, y: 12)
            }
            Divider()
            HStack(spacing: 8) {
                Button("Smaller") { store.scaleSelection(by: 0.9) }
                    .accessibilityLabel("Reduce selection size")
                Button("Larger") { store.scaleSelection(by: 1.1) }
                    .accessibilityLabel("Increase selection size")
            }
            .frame(minHeight: 44)
            .disabled(!store.canWrite)
            Button(store.selectedTextBox == nil ? "Delete selection" : "Delete text box", role: .destructive) {
                store.deleteSelection()
                onDismiss()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(!store.canWrite || store.selection.isEmpty)
            .accessibilityHint("Delete selected ink, text boxes, and shapes. Keep the PDF content unchanged")
            Button("Clear selection") {
                store.clearSelection()
                onDismiss()
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .padding(20)
        .frame(width: 320)
        .presentationCompactAdaptation(.popover)
    }

    private func moveButton(_ title: String, x: CGFloat, y: CGFloat) -> some View {
        Button(title) { store.moveSelection(by: CGPoint(x: x, y: y)) }
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(!store.canWrite)
            .accessibilityLabel("Move selection \(title.lowercased())")
    }

}
