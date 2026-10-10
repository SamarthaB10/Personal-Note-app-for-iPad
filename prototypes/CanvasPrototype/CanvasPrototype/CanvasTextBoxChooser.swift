import SwiftUI

/// A preview does not open the keyboard. The user must confirm one box.
struct CanvasTextBoxChooser: View {
    @ObservedObject var store: CanvasPageStore
    let listHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Choose a text box")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Cancel") { store.cancelTextBoxChoice() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Close the text box list")
            }
            Text("Tap a preview to highlight its box on the page.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(store.textBoxCandidates) { box in
                        textBoxChoiceRow(box)
                    }
                }
            }
            .frame(maxHeight: listHeight)
            Button {
                if let id = store.previewTextBoxID { store.chooseTextBox(id) }
            } label: {
                Text(store.textBoxChoiceStartsEditing ? "Edit text box" : "Select text box")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.previewTextBoxID == nil)
            .accessibilityHint(store.textBoxChoiceStartsEditing
                ? "Open the keyboard for the highlighted box only"
                : "Select the highlighted box only without opening the keyboard")
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(uiColor: .separator))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Text boxes near this point")
    }

    private func textBoxChoiceRow(_ box: CanvasTextBox) -> some View {
        let isPreviewed = store.previewTextBoxID == box.id
        let number = (store.page.textBoxes.firstIndex(where: { $0.id == box.id }) ?? 0) + 1
        let preview = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = preview.isEmpty ? "Empty text box" : preview
        let left = Int(box.frame.minX / CanvasPageGeometry.size.width * 100)
        let top = Int(box.frame.minY / CanvasPageGeometry.size.height * 100)
        return Button { store.previewTextBoxChoice(box.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Box \(number)").fontWeight(.semibold)
                    Spacer(minLength: 0)
                    if isPreviewed { Text("Preview").fontWeight(.semibold) }
                }
                .font(.caption)
                Text(text)
                    .font(.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text("Left \(left)% · Top \(top)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .background(isPreviewed ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isPreviewed ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .accessibilityLabel("Box \(number), \(text), \(left) percent from left, \(top) percent from top")
        .accessibilityHint("Preview this box on the page before you confirm")
        .accessibilityAddTraits(isPreviewed ? .isSelected : [])
    }

}
