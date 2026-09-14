import Foundation

public struct GestureDetector: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var fingerCount: Int
        public var maxTapDuration: TimeInterval
        public var movementTolerance: Double
        public var overshootTolerance: Int
        /// Whether a momentary non-contact reading on the sampled touch
        /// cancels an in-progress tap. With more fingers down at once,
        /// there's more competition for which physical finger the
        /// framework reports first each frame, so a still-settling finger
        /// is more likely to briefly occupy that slot. Disabling this lets
        /// touchCount's own rise and fall be the sole signal for higher
        /// finger counts, where that competition is worse.
        public var requireContactWhileTracking: Bool

        public init(
            fingerCount: Int = 3,
            maxTapDuration: TimeInterval = 0.45,
            movementTolerance: Double = 0.035,
            overshootTolerance: Int = 0,
            requireContactWhileTracking: Bool = true
        ) {
            self.fingerCount = fingerCount
            self.maxTapDuration = maxTapDuration
            self.movementTolerance = movementTolerance
            self.overshootTolerance = overshootTolerance
            self.requireContactWhileTracking = requireContactWhileTracking
        }
    }

    private enum Phase: Sendable {
        case idle
        case tracking(startTime: TimeInterval, refX: Double, refY: Double, lastTouchCount: Int, cancelled: Bool)
        case cooldown
    }

    public var configuration: Configuration
    private var phase: Phase = .idle

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        phase = .idle
    }

    /// Consumes one raw multitouch frame and returns true exactly once for a valid tap.
    /// Touch states 3...5 correspond to make-touch, touching, and break-touch in
    /// MultitouchSupport's long-standing private state model.
    public mutating func ingest(
        touchCount: Int,
        firstTouchState: Int,
        x: Double,
        y: Double,
        timestamp: TimeInterval
    ) -> Bool {
        let fingers = max(2, min(configuration.fingerCount, 5))
        let isPhysicalContact = (3...5).contains(firstTouchState)

        switch phase {
        case .idle:
            // Landing frames don't reliably pass through every intermediate
            // finger count before settling (sampling gaps, or a finger or
            // two touching a beat later than the rest), so start tracking
            // as soon as we reach the target count instead of requiring an
            // exact match.
            guard touchCount >= fingers, isPhysicalContact else {
                return false
            }
            phase = .tracking(
                startTime: timestamp,
                refX: x,
                refY: y,
                lastTouchCount: touchCount,
                cancelled: false
            )
            return false

        case let .tracking(startTime, refX, refY, lastTouchCount, alreadyCancelled):
            var cancelled = alreadyCancelled

            // MultitouchSupport doesn't guarantee the "first" touch keeps
            // referring to the same physical finger across frames; that
            // identity is most likely to shift right when a finger is
            // added or removed. Re-anchor the reference position whenever
            // the touch count changes so such shifts aren't mistaken for a
            // swipe, and only measure movement while the count is steady.
            let touchCountChanged = touchCount != lastTouchCount
            let anchorX = touchCountChanged ? x : refX
            let anchorY = touchCountChanged ? y : refY
            let distance = touchCountChanged ? 0 : hypot(x - anchorX, y - anchorY)

            if touchCount > fingers + configuration.overshootTolerance {
                cancelled = true
            }

            if touchCount >= fingers {
                let elapsed = timestamp - startTime
                if elapsed > configuration.maxTapDuration ||
                    distance > configuration.movementTolerance ||
                    (configuration.requireContactWhileTracking && !isPhysicalContact) {
                    cancelled = true
                }

                phase = .tracking(
                    startTime: startTime,
                    refX: anchorX,
                    refY: anchorY,
                    lastTouchCount: touchCount,
                    cancelled: cancelled
                )
                return false
            }

            // touchCount < fingers: at least one finger has lifted, which
            // marks the end of the gesture.
            let elapsed = timestamp - startTime
            let valid = !cancelled && elapsed <= configuration.maxTapDuration
            phase = .cooldown
            return valid

        case .cooldown:
            if touchCount == 0 {
                phase = .idle
            }
            return false
        }
    }
}
