import XCTest
@testable import MonitorPilot

final class ReconnectPolicyTests: XCTestCase {
    func testOrphanWithLastIDIsCandidate() {
        let c = ReconnectPolicy.candidates(saved: ["dell": (lastID: 2, soft: false)], onlineKeys: ["lg"], onlineIDs: [3])
        XCTAssertEqual(c, [.init(key: "dell", displayID: 2)])
    }
    func testSoftDisconnectedIsNotReconnected() {
        let c = ReconnectPolicy.candidates(saved: ["dell": (lastID: 2, soft: true)], onlineKeys: ["lg"], onlineIDs: [3])
        XCTAssertTrue(c.isEmpty)
    }
    func testOnlineDisplayIsSkipped() {
        let c = ReconnectPolicy.candidates(saved: ["dell": (lastID: 2, soft: false)], onlineKeys: ["dell", "lg"], onlineIDs: [2, 3])
        XCTAssertTrue(c.isEmpty)
    }
    func testIDNowOwnedByAnotherOnlineDisplayIsSkipped() {
        let c = ReconnectPolicy.candidates(saved: ["dell": (lastID: 3, soft: false)], onlineKeys: ["lg"], onlineIDs: [3])
        XCTAssertTrue(c.isEmpty, "ID 3 é o LG agora — não mexer")
    }
    func testWithoutLastIDNothingToDo() {
        let c = ReconnectPolicy.candidates(saved: ["dell": (lastID: nil, soft: false)], onlineKeys: [], onlineIDs: [])
        XCTAssertTrue(c.isEmpty)
    }
}
