import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Persist this record beside editable page data. Never put it in the ink selection.
struct CanvasImportedBackground: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case pdf, image }
    let sourceID: UUID
    let kind: Kind
    let sourcePageIndex: Int
    let bounds: CGRect
    let rotation: Int
    let imageOrientation: Int

    var displayAssetName: String { "\(sourceID.uuidString)-page-\(sourcePageIndex).pdf" }

    var placement: CGRect {
        let size = displayedSize
        let scale = min(612 / size.width, 792 / size.height)
        return CGRect(x: (612 - size.width * scale) / 2, y: (792 - size.height * scale) / 2,
                      width: size.width * scale, height: size.height * scale)
    }

    func validate() throws {
        guard sourcePageIndex >= 0, bounds.width > 0, bounds.height > 0,
              [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].allSatisfy({ $0.isFinite }),
              [0, 90, 180, 270].contains(rotation), (1...8).contains(imageOrientation) else {
            throw CanvasImportError.ioFailure
        }
    }

    var displayedSize: CGSize {
        let swapsAxes = kind == .pdf ? rotation == 90 || rotation == 270 : (5...8).contains(imageOrientation)
        return swapsAxes ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
    }
}

struct CanvasImportSource: Codable, Sendable {
    let id: UUID
    let originalName: String
    let storedName: String
    let byteCount: Int64
    let sha256: String
    var displayAssetNames: [String] = []
    var ownedFileNames: Set<String> {
        Set([storedName, "\(id.uuidString).json"] + displayAssetNames)
    }
}

/// Owns a private staging directory until the store copies and publishes its contents.
struct CanvasStagedImport: Sendable {
    let source: CanvasImportSource
    let directoryURL: URL
    var fileURL: URL { directoryURL.appendingPathComponent(source.storedName) }
}

struct CanvasPreparedImport: Sendable {
    let staged: CanvasStagedImport
    let sourcePageCount: Int
    let pages: [CanvasImportedBackground]
    var omittedPageCount: Int { sourcePageCount - pages.count }
    var countMessage: String {
        if omittedPageCount > 0 {
            return "Imported \(pages.count) of \(sourcePageCount) pages. \(omittedPageCount) pages did not fit within the 300-page limit. The complete source file is kept."
        }
        return "Imported \(pages.count) pages."
    }
}

enum CanvasImportError: Error, LocalizedError, Sendable {
    case localFileRequired, unreadableFile, unsupportedFile, emptyFile, noCapacity
    case passwordRequired, incorrectPassword, invalidPDFPage(Int), invalidImage, multipleImageFrames
    case ioFailure
    var errorDescription: String? {
        switch self {
        case .localFileRequired: "Select a local file."
        case .unreadableFile: "The file could not be read. Existing notebooks are unchanged."
        case .unsupportedFile: "Select a PDF or an image supported by this iPad."
        case .emptyFile: "The file has no pages."
        case .noCapacity: "This notebook has reached the 300-page limit."
        case .passwordRequired: "Enter the PDF password."
        case .incorrectPassword: "The PDF password is incorrect. Try again."
        case .invalidPDFPage(let index): "PDF page \(index + 1) could not be read. No pages were added."
        case .invalidImage: "The image could not be read. No pages were added."
        case .multipleImageFrames: "Select a single-frame image. This image contains more than one frame."
        case .ioFailure: "The import could not be saved. Existing notebooks and the source file are unchanged."
        }
    }
}

/// All file and framework work runs in utility tasks. No PDF object crosses tasks.
/// Supply an app-owned local staging root, separate from published notebook files.
struct CanvasImportAdapter: Sendable {
    let stagingRoot: URL
    static let maximumPageCount = 300

    func stage(_ pickedURL: URL) async throws -> CanvasStagedImport {
        try await utility { try Self.copySource(pickedURL, into: stagingRoot) }
    }

    /// A password failure retains the staged copy for another explicit user attempt.
    /// Do not store or log the password. Separate display assets permit offline reopen without a saved password.
    func prepare(_ staged: CanvasStagedImport, existingPageCount: Int,
                 password: String? = nil) async throws -> CanvasPreparedImport {
        guard (0...Self.maximumPageCount).contains(existingPageCount) else {
            throw CanvasImportError.noCapacity
        }
        let capacity = Self.maximumPageCount - existingPageCount
        guard capacity > 0 else { throw CanvasImportError.noCapacity }
        return try await utility {
            try Self.inspect(staged, capacity: capacity, password: password)
        }
    }

    /// Call only after cancellation, an abandoned password prompt, or successful publication.
    func discard(_ staged: CanvasStagedImport) async throws {
        // Cleanup must finish even when the calling import task is cancelled.
        let cleanup = Task.detached(priority: .utility) {
            let expected = stagingRoot.appendingPathComponent(staged.source.id.uuidString, isDirectory: true)
            guard staged.directoryURL.standardizedFileURL == expected.standardizedFileURL else {
                throw CanvasImportError.ioFailure
            }
            if FileManager.default.fileExists(atPath: expected.path) {
                try FileManager.default.removeItem(at: expected)
            }
        }
        try await cleanup.value
    }

    private func utility<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try operation()
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func copySource(_ url: URL, into root: URL) throws -> CanvasStagedImport {
        guard url.isFileURL else { throw CanvasImportError.localFileRequired }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
        // A generated filename avoids unsafe provider names and path traversal.
        let storedName = "\(id.uuidString).source"
        let destination = directory.appendingPathComponent(storedName)
        var result: Result<CanvasImportSource, Error>?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            result = Result {
                let values = try readableURL.resourceValues(forKeys: [.isRegularFileKey, .isUbiquitousItemKey])
                guard values.isRegularFile == true else { throw CanvasImportError.unreadableFile }
                let input = try FileHandle(forReadingFrom: readableURL)
                defer { try? input.close() }
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                    throw CanvasImportError.ioFailure
                }
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }
                var digest = SHA256()
                var count: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { break }
                    try output.write(contentsOf: data)
                    digest.update(data: data)
                    count += Int64(data.count)
                }
                guard count > 0 else { throw CanvasImportError.emptyFile }
                try output.synchronize()
                try Task.checkCancellation()
                return CanvasImportSource(id: id, originalName: url.lastPathComponent,
                    storedName: storedName, byteCount: count,
                    sha256: digest.finalize().map { String(format: "%02x", $0) }.joined())
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CanvasImportError.unreadableFile }
        let source = try result.get()
        try Task.checkCancellation()
        succeeded = true
        return CanvasStagedImport(source: source, directoryURL: directory)
    }

    private static func inspect(_ staged: CanvasStagedImport, capacity: Int,
                                password: String?) throws -> CanvasPreparedImport {
        try Task.checkCancellation()
        // Detect content, rather than trusting a filename or extension.
        if let document = PDFDocument(url: staged.fileURL) {
            if document.isLocked {
                guard let password else { throw CanvasImportError.passwordRequired }
                guard document.unlock(withPassword: password), !document.isLocked else {
                    throw CanvasImportError.incorrectPassword
                }
            }
            let count = document.pageCount
            guard count > 0 else { throw CanvasImportError.emptyFile }
            var pages: [CanvasImportedBackground] = []
            for index in 0..<min(count, capacity) {
                try Task.checkCancellation()
                let record = try autoreleasepool {
                    guard let page = document.page(at: index) else { throw CanvasImportError.invalidPDFPage(index) }
                    guard let reference = page.pageRef else { throw CanvasImportError.invalidPDFPage(index) }
                    let crop = reference.getBoxRect(.cropBox)
                    let media = reference.getBoxRect(.mediaBox)
                    let bounds = crop.intersection(media)
                    guard valid(bounds), [0, 90, 180, 270].contains(Int(reference.rotationAngle)) else {
                        throw CanvasImportError.invalidPDFPage(index)
                    }
                    let background = CanvasImportedBackground(sourceID: staged.source.id, kind: .pdf,
                        sourcePageIndex: index, bounds: bounds, rotation: Int(reference.rotationAngle), imageOrientation: 1)
                    try makeDisplayAsset(page, background: background, in: staged.directoryURL)
                    return background
                }
                pages.append(record)
            }
            return CanvasPreparedImport(staged: staged, sourcePageCount: count, pages: pages)
        }
        guard let image = CGImageSourceCreateWithURL(staged.fileURL as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(image),
              let identifier = UTType(type as String), identifier.conforms(to: .image) else {
            throw CanvasImportError.unsupportedFile
        }
        guard CGImageSourceGetCount(image) == 1 else { throw CanvasImportError.multipleImageFrames }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw CanvasImportError.invalidImage
        }
        let bounds = CGRect(x: 0, y: 0, width: width.doubleValue, height: height.doubleValue)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        guard valid(bounds), (1...8).contains(orientation) else { throw CanvasImportError.invalidImage }
        try Task.checkCancellation()
        // Decode a bounded preview to detect unreadable pixels without a full-size bitmap.
        guard CGImageSourceCreateThumbnailAtIndex(image, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) != nil else { throw CanvasImportError.invalidImage }
        let page = CanvasImportedBackground(sourceID: staged.source.id, kind: .image,
            sourcePageIndex: 0, bounds: bounds, rotation: 0, imageOrientation: orientation)
        return CanvasPreparedImport(staged: staged, sourcePageCount: 1, pages: [page])
    }


    /// Canonical immutable page assets permit reopen without retaining a PDF password.
    private static func makeDisplayAsset(_ page: PDFPage, background: CanvasImportedBackground,
                                         in directory: URL) throws {
        guard page.pageRef != nil else { throw CanvasImportError.invalidPDFPage(background.sourcePageIndex) }
        let url = directory.appendingPathComponent(background.displayAssetName)
        var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &bounds, nil) else { throw CanvasImportError.ioFailure }
        context.beginPDFPage(nil)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(bounds)
        let frame = background.placement
        // PDF and canvas origins differ. Fit and crop once, before the asset is stored.
        let target = CGRect(x: frame.minX, y: bounds.height - frame.maxY, width: frame.width, height: frame.height)
        context.saveGState()
        context.clip(to: target)
        context.translateBy(x: target.minX, y: target.minY)
        let size = background.displayedSize
        context.scaleBy(x: target.width / size.width, y: target.height / size.height)
        // PDFKit applies the crop origin and page rotation and includes source annotations.
        // Only the new display asset is written. The complete original stays unchanged.
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()
        guard let check = CGPDFDocument(url as CFURL), check.numberOfPages == 1, !check.isEncrypted else {
            throw CanvasImportError.ioFailure
        }
    }

    private static func valid(_ bounds: CGRect) -> Bool {
        !bounds.isNull && !bounds.isEmpty && bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.width.isFinite && bounds.height.isFinite && bounds.width > 0 && bounds.height > 0
            && bounds.maxX.isFinite && bounds.maxY.isFinite
    }
}

/// A dispatch write checks this flag before the atomic index commit.
final class CanvasImportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}
