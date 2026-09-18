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
        XCTAssertEqual(left.ingest(touchCount: 2, firstTouchState: 5, x: 0.3, y: 0.47, timestamp: 1.12), .left)
    }

    func testDiagonalSwipeReportsNothing() {
        var detector = SwipeDetector(configuration: .init(fingerCount: 3, directionBias: 2.0))
        XCTAssertNil(detector.ingest(touchCount: 3, firstTouchState: 4, x: 0.6, y: 0.7, timestamp: 1.00))
        // 45°: neither axis dominates by 2x.
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
