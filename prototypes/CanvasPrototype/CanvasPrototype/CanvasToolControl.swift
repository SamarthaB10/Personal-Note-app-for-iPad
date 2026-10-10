import SwiftUI
import UIKit

/// Toolbar groups use the last saved mode from the shared tool settings.
enum CanvasToolControl: CaseIterable, Identifiable {
    case pen, marker, eraser, textBox, rectangle, lasso
    var id: Self { self }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .marker: "Marker"
        case .eraser: "Eraser"
        case .textBox: "Text box"
        case .rectangle: "Shapes"
        case .lasso: "Lasso"
        }
    }

    @MainActor
    func tool(in store: CanvasPageStore) -> CanvasTool {
        switch self {
        case .pen: .pen
        case .marker: .highlighter
        case .eraser: store.rememberedEraserTool
        case .textBox: .textBox
        case .rectangle: .rectangle
        case .lasso: store.rememberedLassoTool
        }
    }

    @MainActor
    func icon(in store: CanvasPageStore) -> CanvasLucideIcon.Kind {
        switch self {
        case .pen: .pen
        case .marker: .marker
        case .eraser: .eraser
        case .textBox: .text
        case .rectangle: .rectangle
        case .lasso: store.rememberedLassoTool == .boxedLasso ? .box : .lasso
        }
    }

    func contains(_ tool: CanvasTool) -> Bool {
        switch self {
        case .pen: tool == .pen
        case .marker: tool == .highlighter
        case .eraser: tool == .partialEraser || tool == .objectEraser
        case .textBox: tool == .textBox
        case .rectangle: tool == .rectangle
        case .lasso: tool == .freehandLasso || tool == .boxedLasso || tool == .selection
        }
    }
}

/// The native recognizers give hold priority over tap for finger and Pencil input.
struct CanvasNativeToolControl: UIViewRepresentable {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void
    let onHold: () -> Void

    func makeUIView(context: Context) -> CanvasNativeToolButton {
        CanvasNativeToolButton(frame: .zero)
    }

    func updateUIView(_ view: CanvasNativeToolButton, context: Context) {
        view.onTap = onTap
        view.onHold = onHold
        view.accessibilityLabel = label
        view.accessibilityHint = "Tap to use saved settings. Press and hold to change settings"
        view.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }
}

@MainActor
final class CanvasNativeToolButton: UIButton {
    var onTap: (() -> Void)?
    var onHold: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 12
        hold.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber,
                                  UITouch.TouchType.pencil.rawValue as NSNumber,
                                  UITouch.TouchType.indirectPointer.rawValue as NSNumber]
        hold.cancelsTouchesInView = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.allowedTouchTypes = hold.allowedTouchTypes
        tap.delaysTouchesBegan = true
        tap.cancelsTouchesInView = true
        tap.require(toFail: hold)
        addGestureRecognizer(hold)
        addGestureRecognizer(tap)
        // Native button activation retains keyboard and assistive input support.
        addTarget(self, action: #selector(activated), for: .primaryActionTriggered)
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Settings", target: self, selector: #selector(openSettings))
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTap?()
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onHold?()
    }

    @objc private func activated() { onTap?() }

    @objc private func openSettings() -> Bool {
        onHold?()
        return true
    }
}
