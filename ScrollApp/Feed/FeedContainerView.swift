import UIKit

/// Holds the platform web views and takes vertical swipes away from them, so one swipe moves the
/// unified feed instead of a single site's feed. Taps, double-taps and sideways swipes still reach
/// the page.
final class FeedContainerView: UIView, UIGestureRecognizerDelegate {
    /// Finger moved this far since touch-down (negative = up, towards the next video).
    var onDrag: ((CGFloat) -> Void)?
    /// 1 = next, -1 = previous, 0 = not far or fast enough.
    var onSwipe: ((Int) -> Void)?
    /// Off while the page shows a scrollable panel (comments, share sheet).
    var interceptEnabled = true

    private var pan: UIPanGestureRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        // Once the swipe is ours, the page gets touchcancel and abandons its own scroll.
        pan.cancelsTouchesInView = true
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Every web view fills the container; positions are only ever changed through transforms.
    override func layoutSubviews() {
        super.layoutSubviews()
        for view in subviews {
            view.bounds = CGRect(origin: .zero, size: bounds.size)
            view.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    /// UIView's own hook, which also serves as the pan's delegate method.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard interceptEnabled else { return false }
        let velocity = pan.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x) * 1.5
    }

    /// The pages' own scroll views wait for this pan to fail, so a vertical swipe never scrolls a site.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === pan && otherGestureRecognizer is UIPanGestureRecognizer
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let dy = recognizer.translation(in: self).y
        switch recognizer.state {
        case .changed:
            onDrag?(dy)
        case .ended:
            let vy = recognizer.velocity(in: self).y
            let far = bounds.height * 0.2
            let direction: Int
            if dy < -far || (vy < -800 && dy < 0) {
                direction = 1
            } else if dy > far || (vy > 800 && dy > 0) {
                direction = -1
            } else {
                direction = 0
            }
            onSwipe?(direction)
        case .cancelled, .failed:
            onSwipe?(0)
        default:
            break
        }
    }
}
