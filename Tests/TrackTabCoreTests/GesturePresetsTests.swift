import XCTest
@testable import TrackTabCore

/// Runs the shipped detector configurations side by side on the same frames,
/// the way the app does, and checks that each physical gesture fires exactly
/// the one action it should. Guards the cross-detector interactions that
/// per-detector tests can't see.
final class GesturePresetsTests: XCTestCase {
    private enum Action: Equatable {
        case enter, closeWindow, undo, redo, voiceInput, spotlight
    }

    /// (touchCount, firstTouchState, x, y, timestamp)
    private typealias Frame = (Int, Int, Double, Double, Double)

    private func actions(for frames: [Frame]) -> [Action] {
        var tap3 = GestureDetector(configuration: GesturePresets.threeFingerTap)
        var swipe3 = SwipeDetector(configuration: GesturePresets.threeFingerSwipe)
        var tap4 = GestureDetector(configuration: GesturePresets.fourFingerTap)
        var tap5 = GestureDetector(configuration: GesturePresets.fiveFingerTap)
        var fired: [Action] = []
        for (n, state, x, y, t) in frames {
            if tap3.ingest(touchCount: n, firstTouchState: state, x: x, y: y, timestamp: t) {
                fired.append(.enter)
            }
            switch swipe3.ingest(touchCount: n, firstTouchState: state, x: x, y: y, timestamp: t) {
            case .down: fired.append(.closeWindow)
            case .left: fired.append(.undo)
            case .right: fired.append(.redo)
            case .up, nil: break
            }
            if tap4.ingest(touchCount: n, firstTouchState: state, x: x, y: y, timestamp: t) {
                fired.append(.voiceInput)
            }
            if tap5.ingest(touchCount: n, firstTouchState: state, x: x, y: y, timestamp: t) {
                fired.append(.spotlight)
            }
        }
        return fired
    }

    /// A three-finger swipe from (x0, y0) by (dx, dy), ending with a full lift.
    private func threeFingerSwipe(dx: Double, dy: Double, x0: Double = 0.5, y0: Double = 0.6) -> [Frame] {
        [
            (3, 4, x0, y0, 1.00),
            (3, 4, x0 + dx / 2, y0 + dy / 2, 1.06),
            (3, 4, x0 + dx, y0 + dy, 1.12),
            (2, 5, x0 + dx, y0 + dy, 1.14),
            (0, -1, 0, 0, 1.16),
        ]
    }

    // MARK: - Each gesture fires its own action

    func testThreeFingerTapIsEnterOnly() {
        XCTAssertEqual(actions(for: [
            (3, 4, 0.40, 0.40, 1.00),
            (3, 4, 0.41, 0.40, 1.08),
            (2, 5, 0.41, 0.40, 1.12),
            (0, -1, 0, 0, 1.14),
        ]), [.enter])
    }

    func testThreeFingerTapWithJitterAndNonContactFrameIsStillEnter() {
        XCTAssertEqual(actions(for: [
            (3, 4, 0.40, 0.40, 1.00),
            (3, 1, 0.43, 0.41, 1.10),
            (2, 5, 0.43, 0.41, 1.16),
            (0, -1, 0, 0, 1.18),
        ]), [.enter])
    }

    func testThreeFingerSwipeDirectionsMapToTheirActions() {
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: 0, dy: -0.25)), [.closeWindow])
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: -0.25, dy: 0)), [.undo])
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: 0.25, dy: 0)), [.redo])
    }

    func testThreeFingerSwipeUpDoesNothing() {
        // Left to macOS (Mission Control).
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: 0, dy: 0.25)), [])
    }

    func testFourFingerTapIsVoiceInputOnly() {
        XCTAssertEqual(actions(for: [
            (4, 4, 0.40, 0.40, 1.00),
            (4, 4, 0.41, 0.40, 1.10),
            (3, 5, 0.41, 0.40, 1.14),
            (1, 7, 0.41, 0.40, 1.16),
            (0, -1, 0, 0, 1.17),
        ]), [.voiceInput])
    }

    func testFiveFingerTapIsSpotlightOnly() {
        XCTAssertEqual(actions(for: [
            (5, 4, 0.40, 0.40, 1.00),
            (5, 4, 0.42, 0.41, 1.20),
            (4, 5, 0.42, 0.41, 1.25),
            (0, -1, 0, 0, 1.27),
        ]), [.spotlight])
    }

    // MARK: - Regressions

    func testFourFingerTapThatDriftsDoesNotCloseWindow() {
        // Fixed bug: the three-finger swipe tolerated a fourth finger, so a
        // four-finger tap that drifted down while held passed back through
        // three fingers on lift-off and also sent Command-W.
        XCTAssertEqual(actions(for: [
            (3, 4, 0.50, 0.60, 1.00),  // three fingers land first
            (4, 4, 0.50, 0.58, 1.05),  // fourth lands
            (4, 4, 0.50, 0.54, 1.25),  // drift while held, within tap tolerance
            (3, 5, 0.50, 0.51, 1.35),  // lifting: 0.09 below where it started
            (2, 5, 0.50, 0.50, 1.36),
            (0, -1, 0, 0, 1.38),
        ]), [.voiceInput])
    }

    func testTouchGrowingFromThreeToFourFingersIsVoiceInputOnly() {
        XCTAssertEqual(actions(for: [
            (3, 4, 0.40, 0.40, 1.00),
            (4, 4, 0.40, 0.40, 1.04),
            (3, 5, 0.40, 0.40, 1.12),
            (2, 5, 0.40, 0.40, 1.13),
            (0, -1, 0, 0, 1.15),
        ]), [.voiceInput])
    }

    func testFourFingersReadForASingleFrameAreStillNotAThreeFingerTap() {
        // A four-finger touch whose very first frame is also its only frame
        // at four: the three-finger detectors start tracking on that frame,
        // so they must already count it as too many fingers there, or they
        // treat the 3 -> 2 lift that follows as a clean three-finger tap.
        XCTAssertEqual(actions(for: [
            (4, 4, 0.40, 0.40, 1.00),
            (3, 5, 0.40, 0.40, 1.06),
            (2, 5, 0.40, 0.40, 1.08),
            (0, -1, 0, 0, 1.10),
        ]), [.voiceInput])
    }

    func testFifthFingerGrazeFiresExactlyOneAction() {
        // A four-finger tap that briefly touches five is read as a
        // five-finger tap; what matters is it never fires both.
        XCTAssertEqual(actions(for: [
            (4, 4, 0.40, 0.40, 1.00),
            (5, 4, 0.40, 0.40, 1.04),
            (4, 5, 0.40, 0.40, 1.10),
            (0, -1, 0, 0, 1.12),
        ]), [.spotlight])
    }

    func testRealStraightSwipeWithFingerSwitchOnReleaseStillClosesWindow() {
        // Recorded from a real swipe that used to be rejected: the release
        // frame reports a different finger, shifting the position sideways.
        XCTAssertEqual(actions(for: [
            (3, 4, 0.500, 0.700, 1.000),
            (3, 4, 0.520, 0.580, 1.080),
            (3, 4, 0.535, 0.449, 1.165),
            (2, 5, 0.612, 0.550, 1.180),
            (0, -1, 0, 0, 1.190),
        ]), [.closeWindow])
    }

    // MARK: - Direction limits (~27° off an axis)

    func testSlightlyImperfectSwipesStillCount() {
        // ~20° off the axis.
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: 0.073, dy: -0.20)), [.closeWindow])
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: -0.25, dy: 0.09)), [.undo])
    }

    func testClearlyDiagonalSwipesDoNothing() {
        // ~35° and 45° off the axis.
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: 0.14, dy: -0.20)), [])
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: -0.20, dy: -0.20)), [])
    }

    func testShortThreeFingerMoveIsNeitherTapNorSwipe() {
        // Too far to be a tap (> 0.05), too short to be a swipe (< 0.08).
        XCTAssertEqual(actions(for: threeFingerSwipe(dx: 0, dy: -0.065)), [])
    }
}
