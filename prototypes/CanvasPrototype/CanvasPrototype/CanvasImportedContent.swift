import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UIKit

/// Export uses canonical PDF assets, or original image bytes with their fitted frame.
/// Original bytes remain available separately for editable backup and source checks.
struct CanvasImmutableBackground: Sendable {
    let originalBytes: Data
    let displayBytes: Data
    let isPDF: Bool
    let pageNumber: Int
    let box: CGPDFBox
    let frame: CGRect

    /// A bounded, orientation-correct PNG for renderers that cannot bound source image decode.
    /// Export adapters may use this with the same frame. originalBytes keeps the exact source.
    let boundedImageBytes: Data?
}

enum CanvasImportedContent {
    /// Reject links at each app-owned resource boundary, without changing invalid entries.
    static func requireDirectory(_ url: URL) throws {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeDirectory else { throw CanvasImportError.ioFailure }
    }

    static func createDirectory(_ url: URL, in parent: URL) throws {
        try requireDirectory(parent)
        guard url.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL else {
            throw CanvasImportError.ioFailure
        }
        do { try requireDirectory(url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try requireDirectory(url)
        }
    }

    private static func requireResource(_ url: URL, notebookDirectory: URL) throws {
        let sources = sourceDirectory(notebookDirectory: notebookDirectory)
        try requireDirectory(notebookDirectory.deletingLastPathComponent())
        try requireDirectory(notebookDirectory)
        try requireDirectory(sources)
        guard url.deletingLastPathComponent().standardizedFileURL == sources.standardizedFileURL,
              try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
            throw CanvasImportError.ioFailure
        }
    }

    static func sourceDirectory(notebookDirectory: URL) -> URL {
        notebookDirectory.appendingPathComponent("sources", isDirectory: true)
    }

    static func sourceURL(_ background: CanvasImportedBackground, notebookDirectory: URL) -> URL {
        sourceDirectory(notebookDirectory: notebookDirectory).appendingPathComponent("\(background.sourceID.uuidString).source")
    }

    static func displayURL(_ background: CanvasImportedBackground, notebookDirectory: URL) -> URL {
        let directory = sourceDirectory(notebookDirectory: notebookDirectory)
        return directory.appendingPathComponent(background.kind == .pdf ? background.displayAssetName : "\(background.sourceID.uuidString).source")
    }

    /// Call on a utility queue. The full source is streamed for byte count and SHA-256.
    static func validateSource(_ source: CanvasImportSource, notebookDirectory: URL) throws {
        guard source.storedName == "\(source.id.uuidString).source" else { throw CanvasImportError.ioFailure }
        let url = sourceDirectory(notebookDirectory: notebookDirectory).appendingPathComponent(source.storedName)
        try requireResource(url, notebookDirectory: notebookDirectory)
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hash = SHA256()
        var count: Int64 = 0
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            hash.update(data: data)
            count += Int64(data.count)
        }
        guard count == source.byteCount,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == source.sha256 else {
            throw CanvasImportError.ioFailure
        }
    }

    static func validateBackground(_ background: CanvasImportedBackground, notebookDirectory: URL) throws {
        try background.validate()
        let url = displayURL(background, notebookDirectory: notebookDirectory)
        try requireResource(url, notebookDirectory: notebookDirectory)
        if background.kind == .pdf {
            guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted,
                  document.numberOfPages == 1 else { throw CanvasImportError.ioFailure }
        } else {
            guard let image = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(image) == 1 else {
                throw CanvasImportError.invalidImage
            }
        }
    }

    /// Bound each screen bitmap to 1224 × 1584. ImageIO applies all EXIF orientations.
    static func render(_ background: CanvasImportedBackground, notebookDirectory: URL) throws -> UIImage {
        try validateBackground(background, notebookDirectory: notebookDirectory)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 612, height: 792), format: format)
        let url = displayURL(background, notebookDirectory: notebookDirectory)
        if background.kind == .pdf {
            guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else {
                throw CanvasImportError.ioFailure
            }
            return renderer.image { result in
                let context = result.cgContext
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
                context.translateBy(x: 0, y: 792)
                context.scaleBy(x: 1, y: -1)
                context.concatenate(page.getDrawingTransform(.mediaBox,
                    rect: CGRect(x: 0, y: 0, width: 612, height: 792), rotate: 0, preserveAspectRatio: true))
                context.drawPDFPage(page)
            }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CanvasImportError.invalidImage }
        return renderer.image { result in
            result.cgContext.setFillColor(UIColor.white.cgColor)
            result.cgContext.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
            UIImage(cgImage: pixels).draw(in: background.placement)
        }
    }
}

/// One render queue and a 24 MiB cache bound work during page scrolling.
final class CanvasImportedRenderCache: @unchecked Sendable {
    static let shared = CanvasImportedRenderCache()
    private let queue = DispatchQueue(label: "PersonalNotes.import-background", qos: .utility)
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.totalCostLimit = 24 * 1024 * 1024 }

    func image(_ background: CanvasImportedBackground, notebookDirectory: URL) async throws -> UIImage {
        let cancellation = CanvasImportCancellation()
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try cancellation.check()
                        // Validate even a cache hit, so missing display files remain visible.
                        try CanvasImportedContent.validateBackground(background, notebookDirectory: notebookDirectory)
                        let key = CanvasImportedContent.displayURL(background, notebookDirectory: notebookDirectory).path as NSString
                        if let image = self.cache.object(forKey: key) {
                            try cancellation.check()
                            continuation.resume(returning: image)
                            return
                        }
                        try cancellation.check()
                        let image = try autoreleasepool { try CanvasImportedContent.render(background, notebookDirectory: notebookDirectory) }
                        try cancellation.check()
                        self.cache.setObject(image, forKey: key, cost: 1224 * 1584 * 4)
                        continuation.resume(returning: image)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    func immutableBytes(_ background: CanvasImportedBackground, source: CanvasImportSource, notebookDirectory: URL) async throws -> CanvasImmutableBackground {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try CanvasImportedContent.validateSource(source, notebookDirectory: notebookDirectory)
                    try CanvasImportedContent.validateBackground(background, notebookDirectory: notebookDirectory)
                    let original = try Data(contentsOf: CanvasImportedContent.sourceURL(background, notebookDirectory: notebookDirectory))
                    let display = background.kind == .pdf ? try Data(contentsOf: CanvasImportedContent.displayURL(background, notebookDirectory: notebookDirectory)) : original
                    var boundedImage: Data?
                    if background.kind == .image {
                        guard let imageSource = CGImageSourceCreateWithData(original as CFData, nil),
                              let pixels = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: 1600,
                                kCGImageSourceShouldCacheImmediately: true
                              ] as CFDictionary),
                              let data = UIImage(cgImage: pixels).pngData() else { throw CanvasImportError.invalidImage }
                        boundedImage = data
                    }
                    continuation.resume(returning: CanvasImmutableBackground(originalBytes: original,
                        displayBytes: display, isPDF: background.kind == .pdf, pageNumber: 1,
                        box: .mediaBox, frame: background.kind == .pdf ? CGRect(x: 0, y: 0, width: 612, height: 792) : background.placement,
                        boundedImageBytes: boundedImage))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
