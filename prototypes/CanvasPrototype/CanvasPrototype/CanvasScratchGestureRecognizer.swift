import QuartzCore
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Watches Pencil movement without taking ownership of the PencilKit touch.
/// It recognizes rapid back-and-forth movement followed by a short hold.
final class CanvasScratchGestureRecognizer: UIGestureRecognizer {
    var onPencilDown: (() -> Void)?
    var onScratchBegan: (([CGPoint]) -> Void)?
    var onScratchEnded: (([CGPoint]) -> Void)?
    var onScratchCancelled: (() -> Void)?

    private weak var activeTouch: UITouch?
    private(set) var points: [CGPoint] = []
    private var touchStartTime: CFTimeInterval = 0
    private var lastDirectionPoint: CGPoint?
    private var lastDirection: CGPoint?
    private var holdAnchor: CGPoint?
    private var distanceSinceReversal: CGFloat = 0
    private var pathLength: CGFloat = 0
    private var reversalCount = 0
    private var patternQualified = false
    private var holdID = UUID()
    private var didRecognizeScratch = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
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
        touchStartTime = CACurrentMediaTime()
        let point = touch.location(in: view)
        points = [point]
        lastDirectionPoint = point
        lastDirection = nil
        holdAnchor = nil
        distanceSinceReversal = 0
        pathLength = 0
        reversalCount = 0
        patternQualified = false
        didRecognizeScratch = false
        holdID = UUID()
        onPencilDown?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch), let view else { return }
        let point = activeTouch.location(in: view)
        append(point)
        guard !didRecognizeScratch else {
            state = .changed
            return
        }

        updateScratchPattern(at: point)
        if patternIsReady {
            scheduleHoldRecognition(at: point)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch), let view else { return }
        append(activeTouch.location(in: view))
        self.activeTouch = nil
        holdID = UUID()

        if didRecognizeScratch {
            onScratchEnded?(points)
            state = .ended
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        self.activeTouch = nil
        holdID = UUID()
        if didRecognizeScratch {
            onScratchCancelled?()
            state = .cancelled
        } else {
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        activeTouch = nil
        points = []
        didRecognizeScratch = false
        holdID = UUID()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private var patternIsReady: Bool {
        patternQualified
    }

    private func append(_ point: CGPoint) {
        guard let previous = points.last else {
            points.append(point)
            return
        }
        let distance = hypot(point.x - previous.x, point.y - previous.y)
        if distance >= 1.25 {
            points.append(point)
        }
    }

    private func updateScratchPattern(at point: CGPoint) {
        guard let start = lastDirectionPoint else {
            lastDirectionPoint = point
            return
        }

        let vector = CGPoint(x: point.x - start.x, y: point.y - start.y)
        let length = hypot(vector.x, vector.y)
        guard length >= 5 else { return }

        pathLength += length
        distanceSinceReversal += length
        if let lastDirection {
            let lastLength = hypot(lastDirection.x, lastDirection.y)
            let cosine = (lastDirection.x * vector.x + lastDirection.y * vector.y) / max(1, lastLength * length)
            if cosine < -0.55, distanceSinceReversal >= 9 {
                reversalCount += 1
                distanceSinceReversal = 0
            }
        }

        lastDirection = vector
        lastDirectionPoint = point
        if reversalCount >= 3,
           pathLength >= 42,
           CACurrentMediaTime() - touchStartTime <= 1.2 {
            patternQualified = true
        }
    }

    private func scheduleHoldRecognition(at point: CGPoint) {
        if let holdAnchor, hypot(point.x - holdAnchor.x, point.y - holdAnchor.y) <= 3 { return }
        holdAnchor = point
        holdID = UUID()
        let expectedID = holdID
        let holdPoint = point
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard
                let self,
                self.activeTouch != nil,
                self.holdID == expectedID,
                !self.didRecognizeScratch,
                let current = self.points.last,
                hypot(current.x - holdPoint.x, current.y - holdPoint.y) <= 3,
                self.patternIsReady
            else {
                return
            }

            self.didRecognizeScratch = true
            self.state = .began
            self.onScratchBegan?(self.points)
        }
    }
}
