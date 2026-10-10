import SwiftUI

/// Notebook controls remain outside the zoomed page column.
struct CanvasPrototypeRootView: View {
    @ObservedObject var store: CanvasPageStore
    let pages: [CanvasNotebookPage]
    let notebookTitle: String
    let importMessage: String?
    let navigationError: String?
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
    let canDeleteCurrentPage: Bool
    let onDeleteCurrentPage: () -> Void
    let onPageChange: (Int) -> Void
    let onVisiblePageChange: (Int) -> Void
    let onZoomChange: (Int) -> Void
    let onAddPage: () -> Void
    let onAddPageAfterCurrent: () -> Void
    let onImportPDF: () -> Void
    let captureExportSnapshot: @MainActor (NotebookExportScope) async throws -> ExportNotebookSnapshot
    let onDefaultPaperChange: (CanvasPaper) -> Void
    let onAppearanceChange: (CanvasAppearance) -> Void
    @State private var settingsControl: CanvasToolControl?
    @State private var showsSelectionActions = false

    var body: some View {
        VStack(spacing: 0) {
            Text(notebookTitle).font(.headline).lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .accessibilityAddTraits(.isHeader)
            toolBar
            if let importMessage { Text(importMessage).font(.callout).padding(12) }
            if let navigationError {
                Text(navigationError).font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .accessibilityLabel("Notebook error: \(navigationError)")
            }
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

    private var navigationControls: some View {
        Group {
            Button(action: onBack) {
                CanvasToolbarIcon(kind: .home)
            }
            .disabled(isNavigating || isAddingPage || isChangingPaper)
            .accessibilityLabel("Home")
            .accessibilityHint("Return to this notebook’s folder")
            Button(action: onDeleteCurrentPage) {
                CanvasToolbarIcon(kind: .trash)
            }
            .disabled(!canDeleteCurrentPage)
            .accessibilityLabel("Delete current page")
            .accessibilityHint("Ask before moving this page to Trash. Keep at least one page.")
            .help("Delete current page")
            Menu {
                ForEach(1...max(1, pageCount), id: \.self) { number in
                    Button("Page \(number)") { onPageChange(number - 1) }
                }
            } label: {
                CanvasToolbarIcon(kind: .files)
            }
            .disabled(isNavigating)
            .accessibilityLabel("Choose page, current page \(pageNumber) of \(pageCount)")
            .help("Pages")
            Menu {
                Button("Add Page", action: onAddPageAfterCurrent)
                Button("Import PDF", action: onImportPDF)
            } label: {
                CanvasToolbarIcon(kind: .plus)
            }
                .accessibilityLabel("Add page or import PDF")
                .disabled(isNavigating || isAddingPage || isChangingPaper
                          || pageCount >= CanvasNotebook.maximumPageCount)
                .accessibilityHint("Add a page after the current page")
                .help("Add page or import PDF")
            Button(action: onImportPDF) { CanvasToolbarIcon(kind: .fileInput) }
                .accessibilityLabel("Import from Files")
                .help("Import PDF from Files")
                .disabled(isNavigating || isAddingPage || isChangingPaper || pageCount >= CanvasNotebook.maximumPageCount)
            NotebookExportToFilesControl(captureSnapshot: captureExportSnapshot)
                .disabled(isNavigating)
        }
    }

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                navigationControls
                Divider().frame(height: 24).padding(.horizontal, 4)
                ForEach(CanvasToolControl.allCases) { control in toolButton(control) }
                Divider().frame(height: 24).padding(.horizontal, 4)
                paperMenu
                appearanceMenu
                if store.canUndoScratch {
                    Button { store.undoLastScratchErase() } label: {
                        CanvasToolbarIcon(kind: .undo)
                    }
                    .accessibilityLabel("Undo scratch erase")
                    .accessibilityHint("Restore the ink removed by the last scratch erase")
                }
                if !store.selection.isEmpty {
                    Button { showsSelectionActions.toggle() } label: {
                        CanvasToolbarIcon(kind: .settings)
                    }
                    .accessibilityLabel("Selection actions, \(store.selectionSummary)")
                    .popover(isPresented: $showsSelectionActions) {
                        CanvasSelectionActionsView(store: store) { showsSelectionActions = false }
                    }
                }
                if store.editingTextBoxID != nil {
                    Button { store.finishTextEditing() } label: { CanvasToolbarIcon(kind: .check) }
                        .accessibilityLabel("Done")
                        .accessibilityHint("Finish typing in the text box")
                        .help("Finish typing")
                }
                Text("\(zoomPercent)%").font(.caption).monospacedDigit()
                    .frame(minWidth: 44)
                    .accessibilityLabel("Zoom \(zoomPercent) percent")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityLabel("Notebook controls and writing tools")
    }

    private func toolButton(_ control: CanvasToolControl) -> some View {
        let tool = control.tool(in: store)
        let selected = control.contains(store.tool)
        return ZStack {
            CanvasToolbarIcon(kind: control.icon(in: store))
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
        .frame(width: 44, height: 44)
        .help(control.title)
        .popover(isPresented: Binding(
            get: { settingsControl == control },
            set: { if !$0, settingsControl == control { settingsControl = nil } }
        )) {
            CanvasToolSettingsView(store: store, control: control) { settingsControl = nil }
        }
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
        } label: { CanvasToolbarIcon(kind: .notebook) }
        .disabled(isNavigating || isChangingPaper || isAddingPage || !store.canWrite)
        .accessibilityLabel("Paper, current page \(store.page.paper.title), new pages \(defaultPaper.title)")
        .help("Paper")
    }

    private var appearanceMenu: some View {
        Menu {
            ForEach(CanvasAppearance.allCases, id: \.self) { value in
                Button { onAppearanceChange(value) } label: {
                    Text(value == appearance ? "\(value.title) · Selected" : value.title)
                }
            }
        } label: { CanvasToolbarIcon(kind: .sun) }
        .accessibilityLabel("Appearance, \(appearance.title)")
        .accessibilityHint("Change page and control appearance. Keep saved ink colors")
        .help("Appearance")
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
