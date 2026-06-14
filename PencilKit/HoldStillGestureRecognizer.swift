import UIKit

/// Fires once when a touch has stayed (nearly) still for `holdDuration`,
/// regardless of how far it travelled beforehand — i.e. "draw, then hold the
/// end point". A plain `UILongPressGestureRecognizer` can't do this because it
/// fails as soon as the touch moves past its slop while drawing.
final class HoldStillGestureRecognizer: UIGestureRecognizer {
    var holdDuration: TimeInterval = 0.4
    var movementSlop: CGFloat = 8

    private var anchor: CGPoint = .zero
    private var timer: Timer?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        anchor = touch.location(in: view)
        reschedule()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible, let touch = touches.first else { return }
        let p = touch.location(in: view)
        if hypot(p.x - anchor.x, p.y - anchor.y) > movementSlop {
            anchor = p
            reschedule() // movement keeps resetting the hold timer
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        timer?.invalidate(); timer = nil
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        timer?.invalidate(); timer = nil
        state = .cancelled
    }

    override func reset() {
        super.reset()
        timer?.invalidate(); timer = nil
    }

    private func reschedule() {
        timer?.invalidate()
        // Target/selector Timer avoids a @Sendable closure capturing the
        // (non-Sendable, MainActor) recognizer under strict concurrency.
        timer = Timer.scheduledTimer(timeInterval: holdDuration, target: self,
                                     selector: #selector(holdFired), userInfo: nil, repeats: false)
    }

    @objc private func holdFired() {
        guard state == .possible else { return }
        state = .began
    }
}
