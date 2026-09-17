import XCTest
@testable import MonitorPilot

final class RotationPolicyTests: XCTestCase {
    func testNextWraps() {
        XCTAssertEqual(RotationPolicy.next(current: 0, step: 1), 90)
        XCTAssertEqual(RotationPolicy.next(current: 270, step: 1), 0)
        XCTAssertEqual(RotationPolicy.next(current: 0, step: -1), 270)
        XCTAssertEqual(RotationPolicy.next(current: 90, step: 2), 270)
        XCTAssertEqual(RotationPolicy.next(current: 90, step: 4), 90)
        XCTAssertEqual(RotationPolicy.next(current: 0, step: -5), 270)
    }

    func testNormalize() {
        XCTAssertEqual(RotationPolicy.normalize(0), 0)
        XCTAssertEqual(RotationPolicy.normalize(360), 0)
        XCTAssertEqual(RotationPolicy.normalize(-90), 270)
        XCTAssertEqual(RotationPolicy.normalize(89), 90)
        XCTAssertEqual(RotationPolicy.normalize(359), 0)
        XCTAssertEqual(RotationPolicy.normalize(181), 180)
    }

    func testNextFromInvalidCurrentFallsBackToZeroBase() {
        XCTAssertEqual(RotationPolicy.next(current: 45, step: 1), 180)
    }
}
