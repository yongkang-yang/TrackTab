import XCTest
@testable import TrackTabCore

final class SwipeDetectorTests: XCTestCase {
    func testDownwardSwipeFiresOnce() {
        var detector = SwipeDetector(configuration: .init(fingerCount: 3))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.8, timestamp: 1.00))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.5, timestamp: 1.10))
        XCTAssertEqual(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.5, y: 0.4, timestamp: 1.18), .down)
    }

    func testStationaryTapDoesNotFire() {
        var detector = SwipeDetector(configuration: .init(fingerCount: 3))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.5, timestamp: 1.00))
        XCTAssertNil(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.5, y: 0.5, timestamp: 1.05))
    }

    func testHorizontalSwipesReportLeftAndRight() {
        var right = SwipeDetector(configuration: .init(fingerCount: 3))
        XCTAssertNil(right.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.5, timestamp: 1.00))
        XCTAssertNil(right.ingest(touchCount: 3, firstTouchState: 4, x: 0.6, y: 0.52, timestamp: 1.10))
        XCTAssertEqual(right.ingest(touchCount: 2, firstTouchState: 5, x: 0.6, y: 0.52, timestamp: 1.18), .right)

        var left = SwipeDetector(configuration: .init(fingerCount: 3))
        XCTAssertNil(left.ingest(touchCount: 3, firstTouchState: 4, x: 0.6, y: 0.5, timestamp: 1.00))
        XCTAssertNil(left.ingest(touchCount: 3, firstTouchState: 4, x: 0.3, y: 0.47, timestamp: 1.10))
        XCTAssertEqual(left.ingest(touchCount: 2, firstTouchState: 5, x: 0.3, y: 0.47, timestamp: 1.12), .left)
    }

    func testReleaseFrameFingerSwitchDoesNotSkewDirection() {
        // Recorded from a real straight-down swipe that was being rejected:
        // on the frame where a finger lifts, the reported "first" touch
        // switched to a different finger, making the release position look
        // ~37° off vertical. Direction must come from the last frame where
        // all three fingers were still down (~8° off vertical).
        var detector = SwipeDetector(configuration: .init(fingerCount: 3, directionBias: 2.0, overshootTolerance: 0))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.500, y: 0.700, timestamp: 1.000))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.520, y: 0.580, timestamp: 1.080))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.535, y: 0.449, timestamp: 1.165))
        XCTAssertEqual(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.612, y: 0.550, timestamp: 1.180), .down)
    }

    func testDiagonalSwipeReportsNothing() {
        var detector = SwipeDetector(configuration: .init(fingerCount: 3, directionBias: 2.0))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.6, y: 0.7, timestamp: 1.00))
        // 45°: neither axis dominates by 2x. (The travel is well past the
        // minimum distance, so a nil here really is the angle check.)
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.4, y: 0.5, timestamp: 1.10))
        XCTAssertNil(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.4, y: 0.5, timestamp: 1.12))
    }

    func testLongPressDoesNotFire() {
        var detector = SwipeDetector(configuration: .init(fingerCount: 3))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.8, timestamp: 1.00))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.5, timestamp: 2.00))
        XCTAssertNil(detector.ingest(touchCount: 2, firstTouchState: 5, x: 0.5, y: 0.4, timestamp: 2.05))
    }

    func testTapAndSwipeDetectorsOnSameFramesAreMutuallyExclusive() {
        // A real tap: fires the tap detector, stays silent on the swipe detector.
        var tap = GestureDetector(configuration: .init(fingerCount: 3))
        var swipe = SwipeDetector(configuration: .init(fingerCount: 3))
        _ = tap.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00)
        _ = swipe.ingest(touchCount: 3, firstTouchState: 4, x: 0.2, y: 0.2, timestamp: 1.00)
        XCTAssertTrue(tap.ingest(touchCount: 2, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.05))
        XCTAssertNil(swipe.ingest(touchCount: 2, firstTouchState: 5, x: 0.2, y: 0.2, timestamp: 1.05))

        // A real swipe: fires the swipe detector, cancels the tap detector.
        var tap2 = GestureDetector(configuration: .init(fingerCount: 3))
        var swipe2 = SwipeDetector(configuration: .init(fingerCount: 3))
        _ = tap2.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.8, timestamp: 1.00)
        _ = swipe2.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.8, timestamp: 1.00)
        _ = tap2.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.5, timestamp: 1.10)
        _ = swipe2.ingest(touchCount: 3, firstTouchState: 4, x: 0.5, y: 0.5, timestamp: 1.10)
        XCTAssertFalse(tap2.ingest(touchCount: 2, firstTouchState: 5, x: 0.5, y: 0.4, timestamp: 1.18))
        XCTAssertEqual(swipe2.ingest(touchCount: 2, firstTouchState: 5, x: 0.5, y: 0.4, timestamp: 1.18), .down)
    }
}
