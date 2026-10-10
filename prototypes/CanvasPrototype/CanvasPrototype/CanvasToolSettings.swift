import Combine
import CoreGraphics
import Foundation

/// One local settings object keeps tool choices equal across all open pages.
@MainActor
final class CanvasToolSettings: ObservableObject {
    static let shared = CanvasToolSettings()

    @Published var tool: CanvasTool {
        didSet {
            guard tool != oldValue else { return }
            defaults.set(tool.rawValue, forKey: Self.key("selected"))
            if tool == .partialEraser || tool == .objectEraser {
                rememberedEraserTool = tool
                defaults.set(tool.rawValue, forKey: Self.key("eraser"))
            }
            if tool == .freehandLasso || tool == .boxedLasso {
                rememberedLassoTool = tool
                defaults.set(tool.rawValue, forKey: Self.key("lasso"))
            }
            color = savedColor(for: tool)
            inkWidth = savedWidth(for: tool)
        }
    }
    @Published var color: CanvasColor {
        didSet { defaults.set(color.rawValue, forKey: Self.key("\(tool.rawValue).color")) }
    }
    @Published var inkWidth: CGFloat {
        didSet { defaults.set(Double(inkWidth), forKey: Self.key("\(tool.rawValue).width")) }
    }
    @Published var shapeKind: CanvasShapeKind {
        didSet { defaults.set(shapeKind.rawValue, forKey: Self.key("shapeKind")) }
    }
    @Published private(set) var textFontSize: CGFloat
    private(set) var rememberedEraserTool: CanvasTool
    private(set) var rememberedLassoTool: CanvasTool

    private let defaults: UserDefaults
    private var appearance: CanvasAppearance

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let appearance = defaults.string(forKey: CanvasAppearance.defaultsKey)
            .flatMap(CanvasAppearance.init(rawValue:)) ?? .light
        self.appearance = appearance
        let selected = defaults.string(forKey: Self.key("selected")).flatMap(CanvasTool.init(rawValue:)) ?? .pen
        tool = selected
        let fontSize = defaults.double(forKey: Self.key("textBox.fontSize"))
        textFontSize = fontSize.isFinite && fontSize >= 8 && fontSize <= 96 ? CGFloat(fontSize) : 20
        shapeKind = defaults.string(forKey: Self.key("shapeKind"))
            .flatMap(CanvasShapeKind.init(rawValue:)) ?? .triangle
        let savedColor = defaults.string(forKey: Self.key("\(selected.rawValue).color"))
            .flatMap(CanvasColor.init(rawValue:)) ?? Self.defaultColor(for: appearance)
        color = Self.activeColor(savedColor, for: appearance)
        let width = defaults.double(forKey: Self.key("\(selected.rawValue).width"))
        inkWidth = Self.validWidth(width) ?? 3
        let eraser = defaults.string(forKey: Self.key("eraser")).flatMap(CanvasTool.init(rawValue:))
        rememberedEraserTool = eraser == .partialEraser ? .partialEraser : .objectEraser
        let lasso = defaults.string(forKey: Self.key("lasso")).flatMap(CanvasTool.init(rawValue:))
        rememberedLassoTool = lasso == .boxedLasso ? .boxedLasso : .freehandLasso
    }

    func setWidth(_ width: CGFloat) {
        guard let valid = Self.validWidth(Double(width)) else { return }
        inkWidth = valid
    }

    /// This default applies only when the user adds a new text box.
    func setTextFontSize(_ size: CGFloat) {
        guard size.isFinite, (8...96).contains(size) else { return }
        textFontSize = size
        defaults.set(Double(size), forKey: Self.key("textBox.fontSize"))
    }

    /// Change future content settings only. Stored page colors are never updated here.
    func applyAppearance(_ appearance: CanvasAppearance) {
        self.appearance = appearance
        let adjusted = Self.activeColor(color, for: appearance)
        if color != adjusted { color = adjusted }
    }

    private func savedColor(for tool: CanvasTool) -> CanvasColor {
        let saved = defaults.string(forKey: Self.key("\(tool.rawValue).color"))
            .flatMap(CanvasColor.init(rawValue:)) ?? Self.defaultColor(for: appearance)
        return Self.activeColor(saved, for: appearance)
    }

    private static func defaultColor(for appearance: CanvasAppearance) -> CanvasColor {
        appearance == .dark ? .white : .black
    }

    /// A remembered neutral color follows the current paper; other choices stay fixed.
    private static func activeColor(_ color: CanvasColor, for appearance: CanvasAppearance) -> CanvasColor {
        switch (appearance, color) {
        case (.dark, .black): .white
        case (.light, .white): .black
        default: color
        }
    }

    private func savedWidth(for tool: CanvasTool) -> CGFloat {
        Self.validWidth(defaults.double(forKey: Self.key("\(tool.rawValue).width"))) ?? 3
    }

    private static func validWidth(_ width: Double) -> CGFloat? {
        guard width.isFinite, width > 0 else { return nil }
        return CGFloat(min(width, 64))
    }

    private static func key(_ name: String) -> String { "PersonalNotes.tools.\(name)" }
}
