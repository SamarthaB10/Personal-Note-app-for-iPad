import SwiftUI

struct CanvasToolSettingsView: View {
    @ObservedObject var store: CanvasPageStore
    let control: CanvasToolControl
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(control.title) settings").font(.headline).accessibilityAddTraits(.isHeader)
            ScrollView(.vertical) {
                settingsContent
            }
            .frame(maxHeight: 360)
            Button("Done", action: onDone)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(20)
        .frame(width: 320)
        .presentationCompactAdaptation(.popover)
        .onAppear { activateControl() }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if control == .eraser {
                Picker("Eraser mode", selection: $store.tool) {
                    Text("Partial").tag(CanvasTool.partialEraser)
                    Text("Object").tag(CanvasTool.objectEraser)
                }
                .pickerStyle(.segmented).frame(minHeight: 44)
                Text("Tap Eraser to use this mode again.").font(.footnote).foregroundStyle(.secondary)
            } else if control == .lasso {
                Picker("Lasso mode", selection: $store.tool) {
                    Text("Freehand").tag(CanvasTool.freehandLasso)
                    Text("Box").tag(CanvasTool.boxedLasso)
                }
                .pickerStyle(.segmented).frame(minHeight: 44)
                Text("Touch ink to select and move its complete stroke. Use two fingers to scroll or zoom.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                if control == .rectangle {
                    Picker("Shape", selection: Binding(
                        get: { store.shapeKind },
                        set: { activateControl(); store.shapeKind = $0 }
                    )) {
                        ForEach(CanvasShapeKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    Text("Drag to draw the selected shape as ink. Erasers and scratch erase work on this ink.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if control != .textBox {
                    HStack {
                        Text("Width")
                        Spacer()
                        Text("\(Int(store.inkWidth))").monospacedDigit()
                    }
                    Slider(value: widthBinding, in: 1...12, step: 1)
                        .frame(minHeight: 44)
                        .accessibilityLabel("\(control.title) manual width")
                }
                colorChoices
                if control == .textBox {
                    Text("Select Text box, then tap a box to open the keyboard.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if control == .pen || control == .marker || control == .eraser {
                Divider()
                Toggle("Scratch erase on this page", isOn: Binding(
                    get: { store.page.scratchEraseEnabled },
                    set: { store.setScratchEraseEnabled($0) }
                ))
                .frame(minHeight: 44)
                Text("Scratch over ink, then hold the Pencil down to erase. Text boxes and original PDF content stay in place.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
    }

    private var widthBinding: Binding<CGFloat> {
        Binding(
            get: { store.inkWidth },
            set: {
                activateControl()
                store.inkWidth = $0
            }
        )
    }

    /// Settings writes must use this control's tool, including its remembered mode.
    private func activateControl() {
        let tool = control.tool(in: store)
        guard store.tool != tool else { return }
        store.cancelTextBoxChoice()
        if tool != .textBox { store.finishTextEditing() }
        store.tool = tool
    }

    private var colorChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color: \(store.color.title)").font(.subheadline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(CanvasColor.allCases, id: \.self) { value in
                    Button {
                        activateControl()
                        store.color = value
                    } label: {
                        VStack(spacing: 4) {
                            Circle().fill(Color(uiColor: value.uiColor)).frame(width: 28, height: 28)
                                .overlay { Circle().strokeBorder(Color.primary.opacity(0.35)) }
                                .overlay(alignment: .topTrailing) {
                                    if store.color == value {
                                        Text("✓").font(.caption.bold()).foregroundStyle(Color.primary)
                                            .frame(width: 18, height: 18)
                                            .background(Color(uiColor: .systemBackground), in: Circle())
                                    }
                                }
                            Text(value.title).font(.caption2).foregroundStyle(Color.primary)
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(store.color == value ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(value.title)
                    .accessibilityValue(store.color == value ? "Selected" : "")
                    .accessibilityAddTraits(store.color == value ? .isSelected : [])
                }
            }
        }
    }

}
