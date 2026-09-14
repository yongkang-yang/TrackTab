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
}
