import XCTest
@testable import TrackTabCore

final class GestureDetectorTests: XCTestCase {
    func testThreeFingerTapFiresOnce() {
        var detector = GestureDetector()
        XCTAssertFalse(detector.ingest(touchCount: 1, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 2, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.02))
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.04))
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.205, y: 0.2, timestamp: 1.10))
        XCTAssertTrue(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.205, y: 0.2, timestamp: 1.14))
        XCTAssertFalse(detector.ingest(touchCount: 0, firstTouchState: -1, x: 0, y: 0, timestamp: 1.17))
    }

    func testSwipeDoesNotFire() {
        var detector = GestureDetector()
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.30, y: 0.2, timestamp: 1.12))
        XCTAssertFalse(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.30, y: 0.2, timestamp: 1.18))
    }

    func testLongPressDoesNotFire() {
        var detector = GestureDetector()
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.60))
        XCTAssertFalse(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.62))
    }

    func testExtraFingerCancelsGesture() {
        var detector = GestureDetector()
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 4, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.05))
        XCTAssertFalse(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.10))
    }

    func testFourFingerMode() {
        var detector = GestureDetector(configuration: .init(fingerCount: 4))
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 4, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.03))
        XCTAssertTrue(detector.ingest(touchCount: 3, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.10))
    }

    func testLandingThatSkipsPastTargetCountStillTracks() {
        // Frames don't reliably pass through every count while fingers land;
        // with overshoot allowed, jumping straight from 2 to 5 must still
        // start a four-finger tap rather than being missed.
        var detector = GestureDetector(configuration: .init(fingerCount: 4, overshootTolerance: 1))
        XCTAssertFalse(detector.ingest(touchCount: 2, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 5, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.02))
        XCTAssertTrue(detector.ingest(touchCount: 3, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.08))
    }

    func testTouchCountChangeReanchorsMovement() {
        // When a finger lands or lifts, the reported "first" touch can switch
        // to another finger, so the position jumps without real movement.
        // That jump must not count toward the movement limit.
        var detector = GestureDetector(configuration: .init(fingerCount: 3, overshootTolerance: 1))
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 4, firstTouchState: 4, x: 0.6, y: 0.6, timestamp: 1.02))
        XCTAssertFalse(detector.ingest(touchCount: 4, firstTouchState: 4, x: 0.61, y: 0.6, timestamp: 1.05))
        XCTAssertTrue(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.61, y: 0.6, timestamp: 1.10))
    }

    func testMovementWhileCountIsSteadyStillCancels() {
        var detector = GestureDetector(configuration: .init(fingerCount: 4, overshootTolerance: 1))
        XCTAssertFalse(detector.ingest(touchCount: 4, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 4, firstTouchState: 4, x: 0.5, y: 0.2, timestamp: 1.10))
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 5, x: 0.5, y: 0.2, timestamp: 1.14))
    }

    func testMomentaryNonContactFrameIsToleratedWhenConfigured() {
        var detector = GestureDetector(configuration: .init(fingerCount: 5, requireContactWhileTracking: false))
        XCTAssertFalse(detector.ingest(touchCount: 5, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        // A still-settling finger briefly occupies the sampled slot (state 1).
        XCTAssertFalse(detector.ingest(touchCount: 5, firstTouchState: 1, x: 0.2, y: 0.2, timestamp: 1.02))
        XCTAssertTrue(detector.ingest(touchCount: 4, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.08))
    }

    func testMomentaryNonContactFrameCancelsByDefault() {
        var detector = GestureDetector(configuration: .init(fingerCount: 5))
        XCTAssertFalse(detector.ingest(touchCount: 5, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertFalse(detector.ingest(touchCount: 5, firstTouchState: 1, x: 0.2, y: 0.2, timestamp: 1.02))
        XCTAssertFalse(detector.ingest(touchCount: 4, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.08))
    }

    func testFiresAgainOnlyAfterAllFingersLift() {
        var detector = GestureDetector(configuration: .init(fingerCount: 3))
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00))
        XCTAssertTrue(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.05))
        // Fingers wobble back up to three before fully lifting: not a new tap.
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.07))
        XCTAssertFalse(detector.ingest(touchCount: 1, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.09))
        XCTAssertFalse(detector.ingest(touchCount: 0, firstTouchState: -1, x: 0, y: 0, timestamp: 1.10))
        // A real second tap after a full lift does fire.
        XCTAssertFalse(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.50))
        XCTAssertTrue(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.55))
    }
}
