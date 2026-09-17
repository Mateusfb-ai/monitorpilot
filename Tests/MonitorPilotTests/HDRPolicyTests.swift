import XCTest
@testable import MonitorPilot

final class HDRPolicyTests: XCTestCase {
    func testNotManagedDoesNothing() {
        XCTAssertNil(HDRPolicy.shouldApply(saved: nil, current: true))
        XCTAssertNil(HDRPolicy.shouldApply(saved: nil, current: false))
    }

    func testAlreadyMatchingDoesNothing() {
        XCTAssertNil(HDRPolicy.shouldApply(saved: true, current: true))
        XCTAssertNil(HDRPolicy.shouldApply(saved: false, current: false))
    }

    func testMismatchReturnsSavedValue() {
        XCTAssertEqual(HDRPolicy.shouldApply(saved: true, current: false), true)
        XCTAssertEqual(HDRPolicy.shouldApply(saved: false, current: true), false)
    }
}
