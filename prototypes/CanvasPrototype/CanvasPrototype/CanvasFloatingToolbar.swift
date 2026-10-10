import SwiftUI

/// Move only with the handle, so normal tool taps and Pencil input stay independent.
struct CanvasFloatingToolbar<Content: View>: View {
    let availableSize: CGSize
    let selectedIcon: CanvasLucideIcon.Kind
    @ObservedObject var history: CanvasUndoHistory
    let permitsUndo: Bool
    let onUndo: () -> Void
    @ViewBuilder let content: (Bool) -> Content
    @AppStorage("PersonalNotes.toolbar.x") private var fractionX = 0.5
    @AppStorage("PersonalNotes.toolbar.y") private var fractionY = 0.0
    @AppStorage("PersonalNotes.toolbar.vertical") private var vertical = false
    @AppStorage("PersonalNotes.toolbar.collapsed") private var collapsed = false
    @GestureState private var drag = CGSize.zero

    var body: some View {
        let width = collapsed ? 132 : vertical ? 44 : max(132, min(1060, availableSize.width - 16))
        let height = collapsed ? 44 : vertical ? max(132, min(1000, availableSize.height - 16)) : 44
        let base = CGPoint(x: clamp(fractionX * availableSize.width, half: width / 2, limit: availableSize.width),
                           y: clamp(8 + fractionY * max(1, availableSize.height - 16), half: height / 2, limit: availableSize.height))
        let center = CGPoint(x: clamp(base.x + drag.width, half: width / 2, limit: availableSize.width),
                             y: clamp(base.y + drag.height, half: height / 2, limit: availableSize.height))
        let layout = vertical && !collapsed ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            CanvasToolbarIcon(kind: .grip)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                // Use fixed screen coordinates while this handle moves with the dock.
                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .updating($drag) { value, state, transaction in
                        transaction.animation = nil
                        state = value.translation
                    }
                    .onEnded { value in
                        let x = clamp(base.x + value.translation.width, half: width / 2, limit: availableSize.width)
                        let y = clamp(base.y + value.translation.height, half: height / 2, limit: availableSize.height)
                        fractionX = min(1, max(0, x / max(1, availableSize.width)))
                        fractionY = min(1, max(0, (y - 8) / max(1, availableSize.height - 16)))
                        vertical = fractionX > 0.86 || fractionX < 0.14
                    })
                .accessibilityLabel("Move tool bar")
                .accessibilityAction(named: "Dock on right") { fractionX = 1; fractionY = 0.5; vertical = true }
                .accessibilityAction(named: "Dock on left") { fractionX = 0; fractionY = 0.5; vertical = true }
                .accessibilityAction(named: "Move to top") { fractionX = 0.5; fractionY = 0; vertical = false }
                .accessibilityAction(named: "Move to bottom") { fractionX = 0.5; fractionY = 1; vertical = false }
                .frame(width: collapsed ? 32 : 44, height: 44)
            // Retain the export control and its task while this region is collapsed.
            content(vertical)
                .frame(width: collapsed ? 0 : nil, height: collapsed ? 0 : nil)
                .clipped().opacity(collapsed ? 0 : 1)
                .allowsHitTesting(!collapsed).accessibilityHidden(collapsed)
            Button { collapsed.toggle() } label: {
                CanvasToolbarIcon(kind: collapsed ? selectedIcon : .chevronDown)
            }
            .accessibilityLabel(collapsed ? "Expand tool bar" : "Collapse tool bar")
            Button(action: onUndo) { CanvasToolbarIcon(kind: .undo) }
                .disabled(history.count == 0 || history.isUndoing || !permitsUndo)
                .accessibilityLabel("Undo, \(history.count) of 7 steps available")
                .help("Undo last edit")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .frame(width: width, height: height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        .position(center)
        .accessibilityLabel("Floating notebook tool bar")
    }

    private func clamp(_ value: CGFloat, half: CGFloat, limit: CGFloat) -> CGFloat {
        min(max(half + 8, value), max(half + 8, limit - half - 8))
    }
}
