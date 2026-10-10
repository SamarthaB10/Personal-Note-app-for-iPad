import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// An editable image belongs to the page, separate from its fixed imported background.
struct CanvasPageImage: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var frame: CGRect
    let data: Data
}

enum CanvasImageAdapter {
    static let clipboardType = "com.samarthab.personalnotes.page-images"

    static func copiedImages(_ data: Data) throws -> [CanvasPageImage] {
        guard data.count <= 110 * 1024 * 1024 else { throw ImageError.tooLarge }
        let images = try JSONDecoder().decode([CanvasPageImage].self, from: data)
        guard !images.isEmpty, images.count <= 40, images.allSatisfy({
            let frame = $0.frame
            return frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
                && frame.width > 0 && frame.height > 0 && isValid($0.data)
        }) else { throw ImageError.unreadable }
        return images
    }
    enum ImageError: LocalizedError {
        case unreadable, tooLarge
        var errorDescription: String? {
            switch self {
            case .unreadable: "The image could not be read. Saved content is preserved."
            case .tooLarge: "The image is too large. Choose a smaller image."
            }
        }
    }

    /// Decode on a utility task and store one bounded PNG with its orientation applied.
    static func prepare(_ data: Data) async throws -> CanvasPageImage {
        try await Task.detached(priority: .utility) {
            guard data.count <= 100 * 1024 * 1024 else { throw ImageError.tooLarge }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw ImageError.unreadable }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw ImageError.unreadable }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination), output.length <= 16 * 1024 * 1024 else { throw ImageError.tooLarge }
            let ratio = CGFloat(image.height) / CGFloat(image.width)
            let width = min(320, 420 / ratio)
            return CanvasPageImage(frame: CGRect(x: 146, y: 186, width: width, height: width * ratio), data: output as Data)
        }.value
    }

    static func pixelCount(_ data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 2048, height <= 2048 else { return 16_000_001 }
        return width * height
    }

    static func isValid(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 16 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width > 0 && height > 0 && width <= 2048 && height <= 2048
    }
}

/// Keep decoded images stable while ink saves and selection transforms update the page.
@MainActor
final class CanvasImageOverlayView: UIView {
    var images: [CanvasPageImage] = [] {
        didSet {
            let ids = Set(images.map(\.id))
            for id in Array(cache.keys) where !ids.contains(id) { cache.removeValue(forKey: id)?.removeFromSuperview() }
            for image in images {
                if cache[image.id] == nil {
                    let view = UIImageView(image: UIImage(data: image.data))
                    view.isUserInteractionEnabled = false
                    view.contentMode = .scaleToFill
                    cache[image.id] = view
                    addSubview(view)
                }
                if let view = cache[image.id] { bringSubviewToFront(view) }
            }
            updateFrames()
        }
    }
    var selectedIDs: Set<UUID> = [] { didSet { updateFrames() } }
    var selectionTransform = CGAffineTransform.identity { didSet { updateFrames() } }
    private var cache: [UUID: UIImageView] = [:]

    private func updateFrames() {
        for image in images {
            cache[image.id]?.frame = selectedIDs.contains(image.id) ? image.frame.applying(selectionTransform) : image.frame
        }
    }
}
