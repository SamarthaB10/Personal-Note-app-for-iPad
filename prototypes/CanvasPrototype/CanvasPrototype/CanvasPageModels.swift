import CoreGraphics
import Foundation
import PencilKit
import UIKit

enum CanvasPaper: String, CaseIterable, Codable {
    case blank
    case lined
    case grid

    var title: String { rawValue.capitalized }
}

enum CanvasTool: String, CaseIterable, Codable {
    case pen
    case highlighter
    case partialEraser
    case objectEraser
    case textBox
    case rectangle
    case freehandLasso
    case boxedLasso
    case selection

    var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .partialEraser: "Partial eraser"
        case .objectEraser: "Object eraser"
        case .textBox: "Text box"
        case .rectangle: "Shapes"
        case .freehandLasso: "Freehand lasso"
        case .boxedLasso: "Box lasso"
        case .selection: "Selection"
        }
    }

    var capturesFingerInput: Bool {
        self == .textBox || self == .rectangle || self == .freehandLasso || self == .boxedLasso || self == .selection
    }
}

enum CanvasColor: String, CaseIterable, Codable {
    case black
    case blue
    case red
    case green
    case white
    case gray
    case orange
    case yellow
    case purple
    case pink
    case brown
    case cyan
    case charcoal
    case silver
    case navy
    case sky
    case teal
    case mint
    case forest
    case lime
    case olive
    case gold
    case amber
    case coral
    case burgundy
    case rose
    case magenta
    case indigo
    case lavender
    case plum
    case tan
    case cream

    var title: String { rawValue.capitalized }

    // These fixed values preserve saved content when the page appearance changes.
    var uiColor: UIColor {
        switch self {
        case .black: .black
        case .blue: UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)
        case .red: UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)
        case .green: UIColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1)
        case .white: .white
        case .gray: UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)
        case .orange: UIColor(red: 1, green: 0.584, blue: 0, alpha: 1)
        case .yellow: UIColor(red: 1, green: 0.8, blue: 0, alpha: 1)
        case .purple: UIColor(red: 0.686, green: 0.322, blue: 0.871, alpha: 1)
        case .pink: UIColor(red: 1, green: 0.176, blue: 0.333, alpha: 1)
        case .brown: UIColor(red: 0.635, green: 0.518, blue: 0.369, alpha: 1)
        case .cyan: UIColor(red: 0.196, green: 0.678, blue: 0.902, alpha: 1)
        case .charcoal: UIColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 1)
        case .silver: UIColor(red: 0.76, green: 0.78, blue: 0.82, alpha: 1)
        case .navy: UIColor(red: 0.06, green: 0.14, blue: 0.38, alpha: 1)
        case .sky: UIColor(red: 0.45, green: 0.76, blue: 1, alpha: 1)
        case .teal: UIColor(red: 0, green: 0.48, blue: 0.48, alpha: 1)
        case .mint: UIColor(red: 0.54, green: 0.90, blue: 0.72, alpha: 1)
        case .forest: UIColor(red: 0.05, green: 0.34, blue: 0.18, alpha: 1)
        case .lime: UIColor(red: 0.63, green: 0.87, blue: 0.13, alpha: 1)
        case .olive: UIColor(red: 0.42, green: 0.46, blue: 0.08, alpha: 1)
        case .gold: UIColor(red: 0.72, green: 0.53, blue: 0.08, alpha: 1)
        case .amber: UIColor(red: 1, green: 0.69, blue: 0.20, alpha: 1)
        case .coral: UIColor(red: 1, green: 0.46, blue: 0.36, alpha: 1)
        case .burgundy: UIColor(red: 0.48, green: 0.04, blue: 0.16, alpha: 1)
        case .rose: UIColor(red: 1, green: 0.62, blue: 0.72, alpha: 1)
        case .magenta: UIColor(red: 0.88, green: 0.05, blue: 0.70, alpha: 1)
        case .indigo: UIColor(red: 0.27, green: 0.24, blue: 0.75, alpha: 1)
        case .lavender: UIColor(red: 0.73, green: 0.65, blue: 1, alpha: 1)
        case .plum: UIColor(red: 0.40, green: 0.12, blue: 0.38, alpha: 1)
        case .tan: UIColor(red: 0.82, green: 0.65, blue: 0.43, alpha: 1)
        case .cream: UIColor(red: 1, green: 0.94, blue: 0.76, alpha: 1)
        }
    }
}

/// The stored shape choice sets future ink. Completed shapes have no object metadata.
enum CanvasShapeKind: String, CaseIterable, Codable {
    case triangle, square, circle, arrow, rectangle, line, ellipse

    var title: String { rawValue.capitalized }
}

/// Builds one continuous ordinary ink stroke for each precomputed shape.
enum CanvasShapeInk {
    static func locations(kind: CanvasShapeKind, from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else { return [] }
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx.isFinite, dy.isFinite else { return [] }
        if kind == .line { return [start, end] }
        if kind == .arrow {
            let length = hypot(dx, dy)
            guard length.isFinite, length > 0 else { return [] }
            let head = min(28, length * 0.3)
            let ux = dx / length
            let uy = dy / length
            let left = CGPoint(x: end.x - head * ux - head * 0.55 * uy,
                               y: end.y - head * uy + head * 0.55 * ux)
            let right = CGPoint(x: end.x - head * ux + head * 0.55 * uy,
                                y: end.y - head * uy - head * 0.55 * ux)
            // Return along the first wing so both wings and the shaft share one stroke.
            return [start, end, left, end, right]
        }
        var target = end
        if kind == .square || kind == .circle {
            let side = min(abs(dx), abs(dy))
            target = CGPoint(x: start.x + (dx < 0 ? -side : side),
                             y: start.y + (dy < 0 ? -side : side))
        }
        let frame = CGRect(x: min(start.x, target.x), y: min(start.y, target.y),
                           width: abs(target.x - start.x), height: abs(target.y - start.y))
        let topLeft = CGPoint(x: frame.minX, y: frame.minY)
        let topRight = CGPoint(x: frame.maxX, y: frame.minY)
        let bottomRight = CGPoint(x: frame.maxX, y: frame.maxY)
        let bottomLeft = CGPoint(x: frame.minX, y: frame.maxY)
        switch kind {
        case .triangle:
            let top = CGPoint(x: frame.midX, y: frame.minY)
            return [top, bottomRight, bottomLeft, top]
        case .circle, .ellipse:
            return (0...128).map { index in
                let angle = CGFloat(index) * 2 * .pi / 128
                return CGPoint(x: frame.midX + frame.width / 2 * cos(angle),
                               y: frame.midY + frame.height / 2 * sin(angle))
            }
        default:
            return [topLeft, topRight, bottomRight, bottomLeft, topLeft]
        }
    }

    /// Repeated vertices keep the cubic B-spline corners at their intended coordinates.
    static func stroke(locations: [CGPoint], color: CanvasColor, width: CGFloat,
                       smooth: Bool = false) -> PKStroke? {
        guard width.isFinite, width > 0, locations.count >= 2,
              locations.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var samples: [CGPoint] = []
        for (start, end) in zip(locations, locations.dropFirst()) {
            let distance = hypot(end.x - start.x, end.y - start.y)
            guard distance.isFinite else { return nil }
            // Bound the work for loaded content that lies outside the page.
            let steps = Int(min(256, max(1, ceil(distance / 2))))
            if !smooth { samples.append(contentsOf: [start, start]) }
            for step in 0..<steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                samples.append(CGPoint(x: start.x + (end.x - start.x) * fraction,
                                       y: start.y + (end.y - start.y) * fraction))
            }
        }
        if let end = locations.last { samples.append(contentsOf: [end, end, end]) }
        let points = samples.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.01,
                          size: CGSize(width: width, height: width), opacity: 1,
                          force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: color.uiColor),
                              path: PKStrokePath(controlPoints: points, creationDate: Date()),
                              transform: .identity, mask: nil)
        let bounds = stroke.renderBounds
        guard !bounds.isNull, !bounds.isEmpty,
              bounds.minX.isFinite, bounds.maxX.isFinite,
              bounds.minY.isFinite, bounds.maxY.isFinite else { return nil }
        return stroke
    }
}

struct CanvasTextBox: Codable, Hashable, Identifiable {
    var id: UUID
    var text: String
    var frame: CGRect
    var fontSize: CGFloat
    var color: CanvasColor

    init(
        id: UUID = UUID(),
        text: String,
        frame: CGRect,
        fontSize: CGFloat = 20,
        color: CanvasColor = .black
    ) {
        self.id = id
        self.text = text
        self.frame = frame
        self.fontSize = fontSize
        self.color = color
    }
}

struct CanvasShape: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case rectangle
    }

    var id: UUID
    var kind: Kind
    var frame: CGRect
    var color: CanvasColor
    var lineWidth: CGFloat

    var renderBounds: CGRect {
        frame.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
    }

    init(
        id: UUID = UUID(),
        kind: Kind = .rectangle,
        frame: CGRect,
        color: CanvasColor = .blue,
        lineWidth: CGFloat = 3
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.color = color
        self.lineWidth = lineWidth
    }
}

struct CanvasPageData: Codable {
    var inkDrawingData: Data
    var textBoxes: [CanvasTextBox]
    var shapes: [CanvasShape]
    var scratchEraseEnabled: Bool
    var paper: CanvasPaper = .blank

    init(inkDrawingData: Data, textBoxes: [CanvasTextBox], shapes: [CanvasShape],
         scratchEraseEnabled: Bool, paper: CanvasPaper = .blank) {
        self.inkDrawingData = inkDrawingData
        self.textBoxes = textBoxes
        self.shapes = shapes
        self.scratchEraseEnabled = scratchEraseEnabled
        self.paper = paper
    }

    private enum CodingKeys: String, CodingKey {
        case inkDrawingData, textBoxes, shapes, scratchEraseEnabled, paper
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inkDrawingData = try values.decode(Data.self, forKey: .inkDrawingData)
        textBoxes = try values.decode([CanvasTextBox].self, forKey: .textBoxes)
        shapes = try values.decode([CanvasShape].self, forKey: .shapes)
        scratchEraseEnabled = try values.decode(Bool.self, forKey: .scratchEraseEnabled)
        paper = try values.decodeIfPresent(CanvasPaper.self, forKey: .paper) ?? .blank
    }

    static let empty = CanvasPageData(
        inkDrawingData: Data(),
        textBoxes: [],
        shapes: [],
        scratchEraseEnabled: true
    )
}

struct CanvasSelection: Equatable {
    var strokeIndices: Set<Int> = []
    var textBoxIDs: Set<UUID> = []
    var shapeIDs: Set<UUID> = []

    var isEmpty: Bool {
        strokeIndices.isEmpty && textBoxIDs.isEmpty && shapeIDs.isEmpty
    }
}

enum CanvasPageGeometry {
    static let size = CGSize(width: 612, height: 792)
}
