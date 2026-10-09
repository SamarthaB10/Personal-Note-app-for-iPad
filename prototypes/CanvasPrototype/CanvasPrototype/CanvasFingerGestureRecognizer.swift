import UIKit
import UIKit.UIGestureRecognizerSubclass

enum CanvasFingerGestureEvent {
    case began(CGPoint)
    case changed([CGPoint])
    case ended([CGPoint])
    case cancelled
}

/// Captures one finger path for page tools. It does not cancel PencilKit input.
final class CanvasFingerGestureRecognizer: UIGestureRecognizer {
    var onEvent: ((CanvasFingerGestureEvent) -> Void)?

    private weak var activeTouch: UITouch?
    private(set) var points: [CGPoint] = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard activeTouch == nil, touches.count == 1, let touch = touches.first, let view else {
            state = .failed
            return
        }
        activeTouch = touch
        let point = touch.location(in: view)
        points = [point]
        state = .began
        onEvent?(.began(point))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch), let view else { return }
        append(activeTouch.location(in: view))
        guard state == .began || state == .changed else { return }
        state = .changed
        onEvent?(.changed(points))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch), let view else { return }
        append(activeTouch.location(in: view))
        self.activeTouch = nil
        onEvent?(.ended(points))
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        self.activeTouch = nil
        onEvent?(.cancelled)
        state = .cancelled
    }

    override func reset() {
        super.reset()
        activeTouch = nil
        points = []
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private func append(_ point: CGPoint) {
        guard let previous = points.last else {
            points.append(point)
            return
        }
        if hypot(point.x - previous.x, point.y - previous.y) >= 1.5 {
            points.append(point)
        }
    }
}
