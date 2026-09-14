import Foundation

public struct GestureDetector: Sendable {
    public struct Configuration: Sendable, Equatable {
        public var fingerCount: Int
        public var maxTapDuration: TimeInterval
        public var movementTolerance: Double

        public init(
            fingerCount: Int = 3,
            maxTapDuration: TimeInterval = 0.45,
            movementTolerance: Double = 0.035
        ) {
            self.fingerCount = fingerCount
            self.maxTapDuration = maxTapDuration
            self.movementTolerance = movementTolerance
        }
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
            guard touchCount == fingers, isPhysicalContact else {
                return false
            }
            phase = .tracking(
                startTime: timestamp,
                startX: x,
                startY: y,
                cancelled: false
            )
            return false

        case let .tracking(startTime, startX, startY, alreadyCancelled):
            var cancelled = alreadyCancelled

            if touchCount > fingers {
                cancelled = true
            }

            if touchCount == fingers {
                let elapsed = timestamp - startTime
                let distance = hypot(x - startX, y - startY)
                if elapsed > configuration.maxTapDuration ||
                    distance > configuration.movementTolerance ||
                    !isPhysicalContact {
                    cancelled = true
                }

                phase = .tracking(
                    startTime: startTime,
                    startX: startX,
                    startY: startY,
                    cancelled: cancelled
                )
                return false
            }

            if touchCount < fingers {
                let elapsed = timestamp - startTime
                let valid = !cancelled && elapsed <= configuration.maxTapDuration
                phase = .cooldown
                return valid
            }

            return false

        case .cooldown:
            if touchCount == 0 {
                phase = .idle
            }
            return false
        }
    }
}
