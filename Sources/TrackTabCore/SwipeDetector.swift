import Foundation

/// Detects a deliberate directional swipe, as opposed to `GestureDetector`
/// which detects a tap (and specifically rejects movement). Kept as a
/// separate type so a swipe-based gesture (e.g. closing a tab) can share a
/// finger count with a tap-based gesture (e.g. a double-tap) without the
/// two interfering: a real tap never travels far enough to register here,
/// and a real swipe travels far enough that the tap detector cancels it.
public struct SwipeDetector: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var fingerCount: Int
        public var minDistance: Double
        public var maxDuration: TimeInterval
        /// How much larger the dominant-axis movement must be than the
        /// cross-axis movement for the swipe to count as along that axis.
        /// Movement that doesn't clear this on either axis is a diagonal
        /// and isn't reported at all.
        public var directionBias: Double
        public var overshootTolerance: Int
        /// Whether a momentary non-contact reading on the sampled touch
        /// cancels an in-progress swipe. See the matching option on
        /// `GestureDetector.Configuration` for why this can be worth
        /// disabling.
        public var requireContactWhileTracking: Bool

        public init(
            fingerCount: Int = 3,
            minDistance: Double = 0.08,
            maxDuration: TimeInterval = 0.8,
            directionBias: Double = 1.2,
            overshootTolerance: Int = 1,
            requireContactWhileTracking: Bool = true
        ) {
            self.fingerCount = fingerCount
            self.minDistance = minDistance
            self.maxDuration = maxDuration
            self.directionBias = directionBias
            self.overshootTolerance = overshootTolerance
            self.requireContactWhileTracking = requireContactWhileTracking
        }
    }

    public enum Direction: Sendable, Equatable {
        case up
        case down
        case left
        case right
    }

    private enum Phase: Sendable {
        case idle
        case tracking(startTime: TimeInterval, startX: Double, startY: Double, cancelled: Bool)
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

    /// Consumes one raw multitouch frame and returns the swipe direction
    /// exactly once, when a valid swipe completes.
    ///
    /// Coordinates follow MultitouchSupport's normalized space, where x
    /// increases from left to right and y increases from bottom to top; a
    /// downward swipe therefore decreases y.
    public mutating func ingest(
        touchCount: Int,
        firstTouchState: Int,
        x: Double,
        y: Double,
        timestamp: TimeInterval
    ) -> Direction? {
        let fingers = max(2, min(configuration.fingerCount, 5))
        let isPhysicalContact = (3...5).contains(firstTouchState)

        switch phase {
        case .idle:
            guard touchCount >= fingers, isPhysicalContact else {
                return nil
            }
            phase = .tracking(startTime: timestamp, startX: x, startY: y, cancelled: false)
            return nil

        case let .tracking(startTime, startX, startY, alreadyCancelled):
            var cancelled = alreadyCancelled
            let elapsed = timestamp - startTime

            if touchCount > fingers + configuration.overshootTolerance {
                cancelled = true
            }
            if elapsed > configuration.maxDuration ||
                (configuration.requireContactWhileTracking && !isPhysicalContact) {
                cancelled = true
            }

            if touchCount >= fingers {
                phase = .tracking(startTime: startTime, startX: startX, startY: startY, cancelled: cancelled)
                return nil
            }

            // touchCount < fingers: at least one finger lifted, ending the swipe.
            phase = .cooldown
            guard !cancelled else { return nil }

            let dx = x - startX
            let dy = y - startY
            guard hypot(dx, dy) >= configuration.minDistance else { return nil }
            if abs(dy) >= abs(dx) * configuration.directionBias {
                return dy < 0 ? .down : .up
            }
            if abs(dx) >= abs(dy) * configuration.directionBias {
                return dx < 0 ? .left : .right
            }
            return nil

        case .cooldown:
            if touchCount == 0 {
                phase = .idle
            }
            return nil
        }
    }
}
