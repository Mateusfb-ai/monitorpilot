import XCTest
@testable import MonitorPilot

final class AmbientServiceTests: XCTestCase {
    func testUnknownDisplayIsNotSupported() {
        XCTAssertFalse(AmbientService.isSupported(0xDEAD_BEEF))
        XCTAssertNil(AmbientService.enabled(0xDEAD_BEEF))
    }

    func testAvailabilityIsConsistent() {
        if !AmbientService.isAvailable {
            XCTAssertFalse(AmbientService.isSupported(CGMainDisplayID()))
        } else {
            _ = AmbientService.enabled(CGMainDisplayID())
        }
    }
}
