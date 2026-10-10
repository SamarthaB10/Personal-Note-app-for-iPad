import SwiftUI

/// Notebook controls remain outside the zoomed page column.
struct CanvasPrototypeRootView: View {
    @ObservedObject var store: CanvasPageStore
    let pages: [CanvasNotebookPage]
    let notebookTitle: String
    let pageNumber: Int
    let pageCount: Int
    let defaultPaper: CanvasPaper
    let isNavigating: Bool
    let isAddingPage: Bool
    let isChangingPaper: Bool
    let appearance: CanvasAppearance
    let zoomPercent: Int
    let scrollRequest: CanvasNotebookScrollRequest?
    let onBack: () -> Void
    let onPageChange: (Int) -> Void
    let onVisiblePageChange: (Int) -> Void
    let onZoomChange: (Int) -> Void
    let onAddPage: () -> Void
    let onAddPageAfterCurrent: () -> Void
    let onImportPDF: () -> Void
    let onDefaultPaperChange: (CanvasPaper) -> Void
    let onAppearanceChange: (CanvasAppearance) -> Void
    @State private var settingsControl: CanvasToolControl?
    @State private var showsSelectionActions = false

    var body: some View {
        VStack(spacing: 0) {
            header
            toolBar
            if store.actionMessage != nil || !store.canWrite || store.hasSaveError {
                saveStatus
            }
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                if index + 1 != pageNumber {
                    CanvasPageSaveErrorRow(store: page.store, pageNumber: index + 1)
                }
            }
            GeometryReader { geometry in
                CanvasNotebookScrollView(
                    pages: pages, appearance: appearance,
                    isAddingPage: isAddingPage,
                    canAddPage: pageCount < CanvasNotebook.maximumPageCount && !isNavigating && !isChangingPaper,
                    scrollRequest: scrollRequest,
                    onVisiblePageChange: onVisiblePageChange, onZoomChange: onZoomChange,
                    onAddPage: onAddPage
                )
                .overlay(alignment: .bottomTrailing) {
                    if !store.textBoxCandidates.isEmpty {
                        CanvasTextBoxChooser(store: store, listHeight: min(240, max(88, geometry.size.height - 180)))
                            .frame(width: min(340, max(0, geometry.size.width - 24)))
                            .padding(12)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .onChange(of: pageNumber) { _, _ in
            showsSelectionActions = false
            settingsControl = nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                CanvasLucideIcon(kind: .home).frame(width: 44, height: 44)
            }
            .disabled(isNavigating || isAddingPage || isChangingPaper)
            .accessibilityLabel("Home")
            .accessibilityHint("Return to this notebook’s folder")
            VStack(alignment: .leading, spacing: 2) {
                Text(notebookTitle).font(.headline).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text("Page \(pageNumber) of \(pageCount)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(1...max(1, pageCount), id: \.self) { number in
                    Button("Page \(number)") { onPageChange(number - 1) }
                }
            } label: {
                Text("Pages").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(isNavigating)
            .accessibilityLabel("Choose page, current page \(pageNumber) of \(pageCount)")
            Menu {
                Button("Add Page", action: onAddPageAfterCurrent)
                Button("Import PDF", action: onImportPDF)
            } label: {
                CanvasLucideIcon(kind: .plus).frame(width: 44, height: 44)
            }
                .accessibilityLabel("Add page or import PDF")
                .disabled(isNavigating || isAddingPage || isChangingPaper
                          || pageCount >= CanvasNotebook.maximumPageCount)
                .accessibilityHint("Add a page after the current page")
            Button("Import from Files", action: onImportPDF)
                .frame(minHeight: 44)
                .disabled(isNavigating || isAddingPage || isChangingPaper || pageCount >= CanvasNotebook.maximumPageCount)
            Text("\(zoomPercent)%")
                .font(.subheadline).monospacedDigit().frame(minWidth: 44)
                .accessibilityLabel("Zoom \(zoomPercent) percent")
            if store.editingTextBoxID != nil {
                Button("Done") { store.finishTextEditing() }
                    .fontWeight(.semibold).frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Finish typing in the text box")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color(uiColor: .systemBackground))
    }

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(CanvasToolControl.allCases) { control in toolButton(control) }
                Divider().frame(height: 28).padding(.horizontal, 8)
                paperMenu
                appearanceMenu
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
                    .popover(isPresented: $showsSelectionActions) {
                        CanvasSelectionActionsView(store: store) { showsSelectionActions = false }
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
        }
        .frame(height: 56)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityLabel("Notebook tools")
    }

    private func toolButton(_ control: CanvasToolControl) -> some View {
        let tool = control.tool(in: store)
        let selected = control.contains(store.tool)
        return ZStack {
            toolLabel(icon: control.icon(in: store), title: control.title)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            CanvasNativeToolControl(
                label: "\(control.title), \(tool.title)", isSelected: selected,
                onTap: { selectTool(control.tool(in: store)) },
                onHold: {
                    selectTool(control.tool(in: store))
                    settingsControl = control
                }
            )
        }
        .frame(width: 60, height: 52)
        .popover(isPresented: Binding(
            get: { settingsControl == control },
            set: { if !$0, settingsControl == control { settingsControl = nil } }
        )) {
            CanvasToolSettingsView(store: store, control: control) { settingsControl = nil }
        }
    }

    private func toolLabel(icon: CanvasLucideIcon.Kind, title: String) -> some View {
        VStack(spacing: 3) {
            CanvasLucideIcon(kind: icon)
            Text(title).font(.caption2).lineLimit(1)
        }
        .frame(width: 60, height: 52)
        .contentShape(Rectangle())
    }

    private var paperMenu: some View {
        Menu {
            Section("Current page: \(store.page.paper.title)") {
                ForEach(CanvasPaper.allCases, id: \.self) { paper in
                    Button { store.setPaper(paper) } label: {
                        Text(paper == store.page.paper ? "\(paper.title) · Selected" : paper.title)
                    }
                }
            }
            Section("New pages: \(defaultPaper.title)") {
                ForEach(CanvasPaper.allCases, id: \.self) { paper in
                    Button { onDefaultPaperChange(paper) } label: {
                        Text(paper == defaultPaper ? "\(paper.title) · Selected" : paper.title)
                    }
                }
            }
        } label: { toolLabel(icon: .notebook, title: "Paper") }
        .disabled(isNavigating || isChangingPaper || isAddingPage || !store.canWrite)
        .accessibilityLabel("Paper, current page \(store.page.paper.title), new pages \(defaultPaper.title)")
    }

    private var appearanceMenu: some View {
        Menu {
            ForEach(CanvasAppearance.allCases, id: \.self) { value in
                Button { onAppearanceChange(value) } label: {
                    Text(value == appearance ? "\(value.title) · Selected" : value.title)
                }
            }
        } label: { toolLabel(icon: .settings, title: appearance.title) }
        .accessibilityLabel("Appearance, \(appearance.title)")
        .accessibilityHint("Change page and control appearance. Keep saved ink colors")
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

    private func selectTool(_ tool: CanvasTool) {
        store.cancelTextBoxChoice()
        if tool != .textBox { store.finishTextEditing() }
        store.tool = tool
    }
}

/// Each row observes its page even when that page is outside the visible canvas.
private struct CanvasPageSaveErrorRow: View {
    @ObservedObject var store: CanvasPageStore
    let pageNumber: Int

    var body: some View {
        if store.hasSaveError {
            Text("Page \(pageNumber): \(store.saveStatus)")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground))
                .accessibilityLabel("Page \(pageNumber) save error: \(store.saveStatus)")
        }
    }
}
