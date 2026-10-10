import UIKit

/// Folder colors use the shared fixed palette, with readable sidebar shades in each mode.
/// This display mapping does not change any saved ink or text color.
enum CanvasFolderColor: String, Codable, CaseIterable, Identifiable {
    case blue, teal, green, gold, coral, rose, purple, indigo, brown, gray

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var uiColor: UIColor {
        UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let shade: CanvasColor
            switch self {
            case .blue: shade = dark ? .sky : .blue
            case .teal: shade = dark ? .cyan : .teal
            case .green: shade = dark ? .mint : .forest
            case .gold: shade = dark ? .amber : .gold
            case .coral: shade = dark ? .coral : .red
            case .rose: shade = dark ? .rose : .pink
            case .purple: shade = .purple
            case .indigo: shade = dark ? .lavender : .indigo
            case .brown: shade = dark ? .tan : .brown
            case .gray: shade = dark ? .silver : .gray
            }
            return shade.uiColor
        }
    }
}
