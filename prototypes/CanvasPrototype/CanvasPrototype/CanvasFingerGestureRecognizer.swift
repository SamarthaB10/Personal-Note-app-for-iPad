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
    /// A transform needs only its endpoints; a lasso retains its complete path.
    var recordsFullPath = true

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
        if let activeTouch {
            // A second finger belongs to notebook pinch or pan, never to a page path.
            if activeTouch.type == .direct { cancelPath() }
            return
        }
        guard touches.count == 1, let touch = touches.first, let view else {
            state = .failed
            return
        }
        if touch.type == .direct,
           (event.allTouches?.filter { $0.type == .direct && $0.phase != .ended && $0.phase != .cancelled }.count ?? 0) > 1 {
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
        if activeTouch.type == .direct, notebookGestureIsActive(from: view) {
            cancelPath()
            return
        }
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
        let hadActiveTouch = activeTouch != nil
        super.reset()
        activeTouch = nil
        points = []
        recordsFullPath = true
        // A second touch or a disabled tool can stop a path without touchesCancelled.
        if hadActiveTouch { onEvent?(.cancelled) }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private func cancelPath() {
        activeTouch = nil
        onEvent?(.cancelled)
        state = .cancelled
    }

    /// An ancestor scroll view owns navigation. Cancel its page preview before it can commit.
    private func notebookGestureIsActive(from view: UIView) -> Bool {
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                let pan = scrollView.panGestureRecognizer.state
                let pinch = scrollView.pinchGestureRecognizer?.state
                if pan == .began || pan == .changed || pinch == .began || pinch == .changed { return true }
            }
            ancestor = current.superview
        }
        return false
    }

    private func append(_ point: CGPoint) {
        if !recordsFullPath, let start = points.first {
            points = [start, point]
            return
        }
        guard let previous = points.last else {
            points.append(point)
            return
        }
        if hypot(point.x - previous.x, point.y - previous.y) >= 1.5 {
            points.append(point)
        }
    }
}
