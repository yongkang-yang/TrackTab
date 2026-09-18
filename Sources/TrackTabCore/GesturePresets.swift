import Foundation

/// The detector configurations TrackTab actually ships with. They live here
/// rather than in the app target so tests exercise the exact same values:
/// several of them only stay correct together (e.g. the three-finger swipe
/// and the four-finger tap must not both claim a four-finger touch), and a
/// test with its own copy of the numbers wouldn't notice when one changes.
public enum GesturePresets {
    /// Three-finger tap (Enter). Loosened the same way as the other tap
    /// gestures: a bit more slack on timing/jitter, and don't cancel on a
    /// momentary non-contact reading on the sampled touch. Movement
    /// tolerance stays well under the swipe's minimum travel (0.08) so a real
    /// tap here still can't also register as a three-finger swipe.
    public static let threeFingerTap = GestureDetector.Configuration(
        fingerCount: 3,
        maxTapDuration: 0.55,
        movementTolerance: 0.05,
        requireContactWhileTracking: false
    )

    /// Three-finger swipe (down: close window, left: undo, right: redo).
    ///
    /// overshootTolerance explicitly 0 (SwipeDetector's own default is 1):
    /// this swipe shares its finger count with a real, distinct 4-finger
    /// gesture (voice input), so it must not tolerate the touch count
    /// reaching 4 the way an unshared finger count could. Without this, a
    /// real 4-finger tap that drifts slightly while held (natural over its
    /// ~0.5s duration) can pass through touchCount 3 on lift-off and get
    /// misread as this swipe.
    ///
    /// directionBias raised from the type's default (1.2, which accepts up to
    /// ~40° off an axis) to 2.0 (~27°) so a clearly diagonal swipe doesn't
    /// count as a direction. 3.0 (~18°) was tried and rejected too many real
    /// swipes, though that was before the release-frame finger-switch fix and
    /// likely partly caused by it.
    public static let threeFingerSwipe = SwipeDetector.Configuration(
        fingerCount: 3,
        directionBias: 2.0,
        overshootTolerance: 0,
        requireContactWhileTracking: false
    )

    /// Four-finger tap (voice input). Same loosening as the three-finger tap.
    /// Overshoot tolerance stays at 0 (the default) so a brief 5th-finger
    /// graze still cancels this one instead of also arming the five-finger
    /// gesture at the same time.
    public static let fourFingerTap = GestureDetector.Configuration(
        fingerCount: 4,
        maxTapDuration: 0.55,
        movementTolerance: 0.05,
        requireContactWhileTracking: false
    )

    /// Five-finger tap (Left Command + Space). 5 is the hardware ceiling
    /// (fingerCount is capped at 5), so unlike the 3/4-finger gestures there's
    /// no room above it to land on by overshooting — all five fingers have to
    /// be read as touching in the same frame, which happens less reliably than
    /// landing on a lower count. Give it more slack on timing and jitter to
    /// compensate.
    public static let fiveFingerTap = GestureDetector.Configuration(
        fingerCount: 5,
        maxTapDuration: 0.7,
        movementTolerance: 0.08,
        requireContactWhileTracking: false
    )
}
