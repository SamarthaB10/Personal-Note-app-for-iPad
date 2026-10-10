import Foundation
import CoreGraphics
import PencilKit
import UIKit

struct ExportRGBA: Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
    var color: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}

enum ExportPaper: Sendable { case blank, lined, grid }

/// The import adapter supplies the same crop box and placement as the canvas.
/// Data is an immutable copy of the source. Export never opens a source for writing.
enum ExportBackground: Sendable {
    case paper(ExportPaper, dark: Bool)
    case pdf(data: Data, pageNumber: Int, box: CGPDFBox, frame: CGRect)
    case image(data: Data, frame: CGRect)
}

struct ExportTextBox: Sendable {
    let text: String
    let frame: CGRect
    let fontSize: CGFloat
    let color: ExportRGBA
}

/// Only old stored rectangles use this type. New shapes are in the drawing.
struct ExportLegacyRectangle: Sendable {
    let frame: CGRect
    let width: CGFloat
    let color: ExportRGBA
}

enum ExportInk: Sendable {
    case drawing(PKDrawing)
    case data(Data)
    func decoded() throws -> PKDrawing {
        switch self {
        case let .drawing(drawing): return drawing
        case let .data(data): return data.isEmpty ? PKDrawing() : try PKDrawing(data: data)
        }
    }
}

struct ExportPageSnapshot: Sendable {
    let id: UUID
    let size: CGSize
    let background: ExportBackground
    let ink: ExportInk
    let textBoxes: [ExportTextBox]
    let legacyRectangles: [ExportLegacyRectangle]
}

/// Capture the ordered pages once. Do not pass stores, canvases, or UIKit views.
struct ExportNotebookSnapshot: Sendable {
    let title: String
    let pages: [ExportPageSnapshot]
}

struct ExportPDFArtifact: Identifiable, Sendable {
    let id: UUID
    let url: URL
    /// Remove only this export's directory after the Files picker closes.
    func removeTemporaryCopy() throws {
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

enum ExportPDFError: LocalizedError {
    case emptyNotebook, invalidPage, invalidBackground, invalidInk, cannotCreatePDF, incompletePDF
    var errorDescription: String? {
        switch self {
        case .emptyNotebook: "There are no pages to export."
        case .invalidPage: "A page has invalid size or content. Export stopped."
        case .invalidBackground: "A source background could not be read. Export stopped."
        case .invalidInk: "Page ink could not be rendered. Export stopped."
        case .cannotCreatePDF: "The PDF could not be created. Check free storage."
        case .incompletePDF: "The PDF is incomplete. No file was exported."
        }
    }
}

/// Serial utility work bounds rendering load. The live canvas stays on the main actor.
final class NotebookPDFExporter: Sendable {
    private let queue = DispatchQueue(label: "PersonalNotes.pdf-export", qos: .utility)

    func export(_ snapshot: ExportNotebookSnapshot) async throws -> ExportPDFArtifact {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try Self.render(snapshot)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// File removal uses the same utility queue as PDF output.
    func removeTemporaryCopy(_ artifact: ExportPDFArtifact) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try artifact.removeTemporaryCopy()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func render(_ snapshot: ExportNotebookSnapshot) throws -> ExportPDFArtifact {
        guard !snapshot.pages.isEmpty else { throw ExportPDFError.emptyNotebook }
        let id = UUID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotebookPDF-\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let url = directory.appendingPathComponent(filename(snapshot.title)).appendingPathExtension("pdf")
        do {
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
                throw ExportPDFError.cannotCreatePDF
            }
            do {
                for page in snapshot.pages {
                    try autoreleasepool {
                        try validate(page)
                        var bounds = CGRect(origin: .zero, size: page.size)
                        let box = NSData(bytes: &bounds, length: MemoryLayout<CGRect>.size)
                        context.beginPDFPage([kCGPDFContextMediaBox as String: box] as CFDictionary)
                        context.saveGState()
                        // All snapshots use the canvas's top-left, unzoomed page coordinates.
                        context.translateBy(x: 0, y: page.size.height)
                        context.scaleBy(x: 1, y: -1)
                        context.clip(to: bounds)
                        UIGraphicsPushContext(context)
                        defer {
                            UIGraphicsPopContext()
                            context.restoreGState()
                            context.endPDFPage()
                        }
                        // Pencil ink is already fixed RGBA. Do not adapt it to dark mode.
                        var drawingResult: Result<Void, Error> = .success(())
                        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                            drawingResult = Result {
                                try drawBackground(page.background, bounds: bounds, context: context)
                                try drawInk(page.ink.decoded(), bounds: bounds)
                                for shape in page.legacyRectangles {
                                    context.setStrokeColor(shape.color.color.cgColor)
                                    context.setLineWidth(shape.width)
                                    context.stroke(shape.frame)
                                }
                                for box in page.textBoxes {
                                    (box.text as NSString).draw(
                                        in: box.frame.insetBy(dx: 5, dy: 5),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: box.fontSize),
                                                         .foregroundColor: box.color.color])
                                }
                            }
                        }
                        try drawingResult.get()
                    }
                }
                context.closePDF()
            } catch {
                context.closePDF()
                throw error
            }
            guard let document = CGPDFDocument(url as CFURL),
                  document.numberOfPages == snapshot.pages.count else {
                throw ExportPDFError.incompletePDF
            }
            return ExportPDFArtifact(id: id, url: url)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func drawBackground(_ background: ExportBackground, bounds: CGRect,
                                       context: CGContext) throws {
        switch background {
        case let .paper(paper, dark):
            context.setFillColor(UIColor(white: dark ? 0.08 : 1, alpha: 1).cgColor)
            context.fill(bounds)
            guard paper != .blank else { return }
            context.setStrokeColor(UIColor(white: dark ? 0.28 : 0.84, alpha: 1).cgColor)
            context.setLineWidth(0.5)
            let spacing: CGFloat = paper == .lined ? 28 : 24
            context.beginPath()
            for y in stride(from: spacing, through: bounds.height, by: spacing) {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: bounds.width, y: y))
            }
            if paper == .grid {
                for x in stride(from: spacing, through: bounds.width, by: spacing) {
                    context.move(to: CGPoint(x: x, y: 0))
                    context.addLine(to: CGPoint(x: x, y: bounds.height))
                }
            }
            context.strokePath()
        case let .pdf(data, number, box, frame):
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider), !document.isEncrypted,
                  number >= 1, let page = document.page(at: number) else {
                throw ExportPDFError.invalidBackground
            }
            context.setFillColor(UIColor.white.cgColor)
            context.fill(bounds)
            context.saveGState()
            defer { context.restoreGState() }
            context.clip(to: frame)
            // PDF drawing uses a bottom-left origin. This also handles source rotation.
            context.translateBy(x: frame.minX, y: frame.maxY)
            context.scaleBy(x: 1, y: -1)
            context.concatenate(page.getDrawingTransform(box,
                rect: CGRect(origin: .zero, size: frame.size), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
        case let .image(data, frame):
            guard let image = UIImage(data: data) else { throw ExportPDFError.invalidBackground }
            context.setFillColor(UIColor.white.cgColor)
            context.fill(bounds)
            image.draw(in: frame)
        }
    }

    private static func drawInk(_ drawing: PKDrawing, bounds: CGRect) throws {
        guard !drawing.strokes.isEmpty else { return }
        // 216 dpi ink tiles bound transient image memory even on large source pages.
        // Paper, text, and original PDF content remain vector content.
        for y in stride(from: CGFloat.zero, to: bounds.height, by: 512) {
            for x in stride(from: CGFloat.zero, to: bounds.width, by: 512) {
                let tile = CGRect(x: x, y: y, width: min(512, bounds.width - x),
                                  height: min(512, bounds.height - y))
                guard drawing.bounds.intersects(tile) else { continue }
                try autoreleasepool {
                    let image = drawing.image(from: tile, scale: 3)
                    guard image.cgImage != nil else { throw ExportPDFError.invalidInk }
                    image.draw(in: tile)
                }
            }
        }
    }

    private static func validate(_ page: ExportPageSnapshot) throws {
        guard valid(CGRect(origin: .zero, size: page.size)),
              page.size.width <= 14_400, page.size.height <= 14_400,
              page.textBoxes.allSatisfy({ valid($0.frame) && $0.fontSize.isFinite && $0.fontSize > 0 && valid($0.color) }),
              page.legacyRectangles.allSatisfy({ valid($0.frame) && $0.width.isFinite && $0.width > 0 && valid($0.color) }) else {
            throw ExportPDFError.invalidPage
        }
        switch page.background {
        case .paper: break
        case let .pdf(_, _, _, frame), let .image(_, frame):
            guard valid(frame) else { throw ExportPDFError.invalidBackground }
        }
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite
            && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }

    private static func valid(_ color: ExportRGBA) -> Bool {
        [color.red, color.green, color.blue, color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    private static func filename(_ title: String) -> String {
        let safe = title.unicodeScalars.map { scalar -> String in
            CharacterSet.controlCharacters.contains(scalar) || "/\\:".unicodeScalars.contains(scalar) ? "-" : String(scalar)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "Notebook" : String(safe.prefix(100))
    }
}
