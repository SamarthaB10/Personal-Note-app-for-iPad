import CoreGraphics
import Foundation

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
        case .rectangle: "Rectangle"
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

    var title: String { rawValue.capitalized }
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
