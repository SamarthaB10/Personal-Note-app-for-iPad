import Foundation
import PencilKit
import UIKit

struct CanvasExportPageCapture {
    let page: CanvasPageData
    let ink: ExportInk
}

/// Copies editable values without saving or changing the live canvas.
/// Capture page values on the main actor before calling this adapter.
/// Refuse active page gestures. Copy the active text editor without changing its session.
@MainActor
enum CanvasExportSnapshotAdapter {
    enum SnapshotError: LocalizedError {
        case missingPage, invalidColor, activeInput
        var errorDescription: String? {
            switch self {
            case .missingPage: "A notebook page is unavailable. Export stopped."
            case .invalidColor: "A saved color could not be read. Export stopped."
            case .activeInput: "Lift the Pencil and finish the page gesture, then export again."
            }
        }
    }

    static func capture(
        notebook: CanvasNotebook,
        currentPageID: UUID,
        scope: NotebookExportScope,
        pages: [UUID: CanvasPageData],
        liveDrawings: [UUID: PKDrawing] = [:],
        pageSize: (UUID, CanvasPageData) -> CGSize = { _, _ in CanvasPageGeometry.size },
        background: (UUID, CanvasPageData) throws -> ExportBackground
    ) throws -> ExportNotebookSnapshot {
        let ids: [UUID]
        switch scope {
        case .currentPage:
            guard notebook.pageIDs.contains(currentPageID) else { throw SnapshotError.missingPage }
            ids = [currentPageID]
        case .completeNotebook: ids = notebook.pageIDs
        }
        let result = try ids.map { id -> ExportPageSnapshot in
            guard let page = pages[id] else { throw SnapshotError.missingPage }
            // Copy the live PKDrawing value, or decode saved bytes on the render queue.
            let ink = liveDrawings[id].map(ExportInk.drawing) ?? .data(page.inkDrawingData)
            return ExportPageSnapshot(
                id: id, size: pageSize(id, page),
                background: try background(id, page), ink: ink,
                textBoxes: try page.textBoxes.map {
                    ExportTextBox(text: $0.text, frame: $0.frame, fontSize: $0.fontSize,
                                  color: try fixedColor($0.color))
                },
                legacyRectangles: try page.shapes.map {
                    ExportLegacyRectangle(frame: $0.frame, width: $0.lineWidth,
                                          color: try fixedColor($0.color))
                })
        }
        return ExportNotebookSnapshot(title: notebook.title, pages: result)
    }

    static func paperBackground(_ page: CanvasPageData, dark: Bool) -> ExportBackground {
        let paper: ExportPaper
        switch page.paper {
        case .blank: paper = .blank
        case .lined: paper = .lined
        case .grid: paper = .grid
        }
        return .paper(paper, dark: dark)
    }

    private static func fixedColor(_ color: CanvasColor) throws -> ExportRGBA {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            throw SnapshotError.invalidColor
        }
        return ExportRGBA(red: red, green: green, blue: blue, alpha: alpha)
    }
}
