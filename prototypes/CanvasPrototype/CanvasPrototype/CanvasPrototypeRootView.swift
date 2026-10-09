import SwiftUI

struct CanvasPrototypeRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = CanvasPageStore()
    @State private var showsToolSettings = false
    @State private var showsSelectionActions = false
    @State private var showsSaveStatus = false
    @State private var eraserTool: CanvasTool = .partialEraser
    @State private var lassoTool: CanvasTool = .freehandLasso

    var body: some View {
        VStack(spacing: 0) {
            header
            toolBar
            if showsSaveStatus || store.actionMessage != nil || !store.canWrite || store.hasSaveError {
                saveStatus
            }
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    CanvasPageView(store: store)
                        .frame(width: geometry.size.width,
                               height: geometry.size.width * CanvasPageGeometry.size.height / CanvasPageGeometry.size.width)
                }
                .scrollDisabled(store.tool.capturesFingerInput)
                .overlay(alignment: .bottomTrailing) {
                    if !store.textBoxCandidates.isEmpty {
                        textBoxChooser(listHeight: min(240, max(88, geometry.size.height - 180)))
                            .frame(width: min(340, max(0, geometry.size.width - 24)))
                            .padding(12)
                    }
                }
            }
            .accessibilityLabel("Editable page")
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveLifecycleSnapshot() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Page 1")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if store.editingTextBoxID != nil {
                Button("Done") { store.finishTextEditing() }
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
                    .accessibilityHint("Finish typing in the text box")
            }
            Button("Save") {
                showsSaveStatus = true
                store.saveNow()
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(store.isSaving || !store.canWrite)
            .accessibilityHint("Save this page on the iPad")
            Button("Reopen") {
                showsSaveStatus = true
                store.reloadSavedPage()
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(store.isSaving)
            .accessibilityHint("Open the saved page")
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color(uiColor: .systemBackground))
    }

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                toolButton(.pen, icon: .pen, title: "Pen")
                toolButton(.highlighter, icon: .marker, title: "Marker")
                eraserMenu
                toolButton(.textBox, icon: .text, title: "Text box")
                toolButton(.rectangle, icon: .rectangle, title: "Rectangle")
                lassoMenu
                Divider().frame(height: 28).padding(.horizontal, 8)
                colorPicker
                Button {
                    showsToolSettings.toggle()
                } label: {
                    VStack(spacing: 3) {
                        Capsule().frame(width: 22, height: max(2, store.inkWidth / 2))
                            .frame(height: 22)
                        Text("Width \(Int(store.inkWidth))").font(.caption2)
                    }
                    .frame(width: 56, height: 52)
                }
                .accessibilityLabel("Tool settings, width \(Int(store.inkWidth))")
                .popover(isPresented: $showsToolSettings) { toolSettings }
                if store.canUndoScratch {
                    Button { store.undoLastScratchErase() } label: {
                        toolLabel(icon: .undo, title: "Undo")
                    }
                    .accessibilityLabel("Undo scratch erase")
                    .accessibilityHint("Restore the ink removed by the last scratch erase")
                }
                if !store.selection.isEmpty {
                    Button { showsSelectionActions.toggle() } label: {
                        toolLabel(icon: .settings, title: "Selection")
                    }
                    .accessibilityLabel("Selection actions, \(store.selectionSummary)")
                    .popover(isPresented: $showsSelectionActions) { selectionActions }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
        }
        .frame(height: 52)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityLabel("Page tools")
    }

    private func toolButton(_ tool: CanvasTool, icon: CanvasLucideIcon.Kind, title: String) -> some View {
        Button { selectTool(tool) } label: {
            toolLabel(icon: icon, title: title)
                .background(store.tool == tool ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(store.tool == tool ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(store.tool == tool ? .isSelected : [])
    }

    private func toolLabel(icon: CanvasLucideIcon.Kind, title: String) -> some View {
        VStack(spacing: 3) {
            CanvasLucideIcon(kind: icon)
            Text(title).font(.caption2).lineLimit(1)
        }
        .frame(width: 60, height: 52)
        .contentShape(Rectangle())
    }

    private var eraserMenu: some View {
        Menu {
            Button("Partial eraser") { eraserTool = .partialEraser; selectTool(eraserTool) }
            Button("Object eraser") { eraserTool = .objectEraser; selectTool(eraserTool) }
        } label: {
            toolLabel(icon: .eraser, title: "Eraser ▾")
                .background(isErasing ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isErasing ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("Eraser modes, \(eraserTool.title)")
        .accessibilityAddTraits(isErasing ? .isSelected : [])
    }

    private var lassoMenu: some View {
        Menu {
            Button("Freehand lasso") { lassoTool = .freehandLasso; selectTool(lassoTool) }
            Button("Box lasso") { lassoTool = .boxedLasso; selectTool(lassoTool) }
        } label: {
            toolLabel(icon: lassoTool == .boxedLasso ? .box : .lasso, title: "Lasso ▾")
                .background(isSelecting ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isSelecting ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("Lasso modes, \(lassoTool.title)")
        .accessibilityHint("Tap an item to select it. Draw around whole items to select a group. Drag inside the selection to move it. Drag the round handle to resize")
        .accessibilityAddTraits(isSelecting ? .isSelected : [])
    }

    private var colorPicker: some View {
        Menu {
            ForEach(CanvasColor.allCases, id: \.self) { value in
                Button(value.title) { store.color = value }
            }
        } label: {
            VStack(spacing: 3) {
                Circle().fill(color(for: store.color)).frame(width: 22, height: 22)
                Text(store.color.title).font(.caption2)
            }
            .frame(width: 52, height: 52)
        }
        .accessibilityLabel("Ink color, \(store.color.title)")
    }

    private var toolSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tool settings").font(.headline).accessibilityAddTraits(.isHeader)
            HStack {
                Text("Width")
                Spacer()
                Text("\(Int(store.inkWidth))").monospacedDigit()
            }
            Slider(value: $store.inkWidth, in: 1...12, step: 1)
                .accessibilityLabel("Manual ink width")
            Divider()
            Toggle("Scratch erase", isOn: Binding(
                get: { store.page.scratchEraseEnabled },
                set: { store.setScratchEraseEnabled($0) }
            ))
            Text("Scratch over ink, then hold the Pencil down to erase. Text boxes, shapes, and PDF content stay in place.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Done") { showsToolSettings = false }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(20)
        .frame(width: 300)
        .presentationCompactAdaptation(.popover)
    }

    private var selectionActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selection").font(.headline).accessibilityAddTraits(.isHeader)
            Text(store.selectionSummary).font(.footnote).foregroundStyle(.secondary)
            Text("Drag inside the selection to move it. Drag the round handle to resize it.")
                .font(.footnote).foregroundStyle(.secondary)
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
            Button("Delete selection", role: .destructive) {
                store.deleteSelection()
                showsSelectionActions = false
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(store.selection.isEmpty)
            .accessibilityHint("Delete selected ink, text boxes, and shapes. Keep the PDF content unchanged")
            Button("Clear selection") {
                store.clearSelection()
                showsSelectionActions = false
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .padding(20)
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
    }

    private func moveButton(_ title: String, x: CGFloat, y: CGFloat) -> some View {
        Button(title) { store.moveSelection(by: CGPoint(x: x, y: y)) }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel("Move selection \(title.lowercased())")
    }

    private func textBoxChooser(listHeight: CGFloat) -> some View {
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

    private var saveStatus: some View {
        Text(pageStatus)
            .font(.footnote)
            .foregroundStyle(store.canWrite && !store.hasSaveError ? Color.secondary : Color.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground))
            .accessibilityLabel("Page status: \(pageStatus)")
    }

    private var pageStatus: String {
        if !store.canWrite || store.hasSaveError { return store.saveStatus }
        return store.actionMessage ?? store.saveStatus
    }

    private var isErasing: Bool { store.tool == .partialEraser || store.tool == .objectEraser }
    private var isSelecting: Bool { store.tool == .freehandLasso || store.tool == .boxedLasso || store.tool == .selection }

    private func color(for value: CanvasColor) -> Color {
        switch value {
        case .black: .black
        case .blue: .blue
        case .red: .red
        case .green: .green
        }
    }

    private func selectTool(_ tool: CanvasTool) {
        store.cancelTextBoxChoice()
        if tool != .textBox { store.finishTextEditing() }
        store.tool = tool
    }
}
