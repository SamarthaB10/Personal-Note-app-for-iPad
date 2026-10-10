import SwiftUI

/// Reads the live box so repeated changes do not use a stale page snapshot.
struct CanvasTextFormatView: View {
    @ObservedObject var store: CanvasPageStore
    let boxID: UUID

    var body: some View {
        if let box = store.formattingTextBox, box.id == boxID {
            VStack(alignment: .leading, spacing: 12) {
                CanvasTextFontSizeControl(size: Binding(
                    get: { store.formattingTextBox?.fontSize ?? box.fontSize },
                    set: { store.setTextBoxFontSize(boxID, size: $0) }
                ))
                CanvasColorChoicesView(color: Binding(
                    get: { store.formattingTextBox?.color ?? box.color },
                    set: { store.setTextBoxColor(boxID, color: $0) }
                ))
            }
            .disabled(!store.canWrite)
        }
    }
}

struct CanvasTextFontSizeControl: View {
    @Binding var size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font size: \(Double(size).formatted(.number.precision(.fractionLength(0...1)))) pt")
                .font(.subheadline).monospacedDigit()
            Slider(value: $size, in: 8...96, step: 1)
                .frame(minHeight: 44)
                .accessibilityLabel("Text font size")
                .accessibilityValue("\(size.formatted()) points")
        }
    }
}

/// All tool and text controls use the same fixed palette and selection labels.
struct CanvasColorChoicesView: View {
    @Binding var color: CanvasColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color: \(color.title)").font(.subheadline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(CanvasColor.allCases, id: \.self) { value in
                    Button { color = value } label: {
                        VStack(spacing: 4) {
                            Circle().fill(Color(uiColor: value.uiColor)).frame(width: 28, height: 28)
                                .overlay { Circle().strokeBorder(Color.primary.opacity(0.35)) }
                                .overlay(alignment: .topTrailing) {
                                    if color == value {
                                        Text("✓").font(.caption.bold()).foregroundStyle(Color.primary)
                                            .frame(width: 18, height: 18)
                                            .background(Color(uiColor: .systemBackground), in: Circle())
                                    }
                                }
                            Text(value.title).font(.caption2).foregroundStyle(Color.primary)
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(color == value ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(value.title)
                    .accessibilityValue(color == value ? "Selected" : "")
                    .accessibilityAddTraits(color == value ? .isSelected : [])
                }
            }
        }
    }
}
