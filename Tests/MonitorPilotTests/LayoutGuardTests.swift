import XCTest
@testable import MonitorPilot

final class LayoutGuardTests: XCTestCase {
    private let base = DisplaySnapshot(modeID: 887, originX: 0, originY: 0, rotation: 0, mirrorMaster: nil)

    func testNoDiffWhenEqual() {
        XCTAssertTrue(LayoutGuard.diff(saved: base, current: base).isEmpty)
    }

    func testDetectsEachField() {
        var m = base; m.modeID = 900
        XCTAssertEqual(LayoutGuard.diff(saved: base, current: m), [.mode])
        var o = base; o.originX = 1920
        XCTAssertEqual(LayoutGuard.diff(saved: base, current: o), [.origin])
        var r = base; r.rotation = 90
        XCTAssertEqual(LayoutGuard.diff(saved: base, current: r), [.rotation])
        var mi = base; mi.mirrorMaster = 2
        XCTAssertEqual(LayoutGuard.diff(saved: base, current: mi), [.mirror])
    }

    func testDetectsSeveralAtOnce() {
        var c = base; c.originY = 300; c.rotation = 270
        XCTAssertEqual(LayoutGuard.diff(saved: base, current: c), [.origin, .rotation])
    }

    func testSavedModeNilIgnoresMode() {
        var saved = base; saved.modeID = nil
        var current = base; current.modeID = 12
        XCTAssertTrue(LayoutGuard.diff(saved: saved, current: current).isEmpty)
    }

    func testCooldown() {
        let now = Date()
        XCTAssertTrue(LayoutGuard.shouldReapply(lastReapply: nil, now: now))
        XCTAssertFalse(LayoutGuard.shouldReapply(lastReapply: now.addingTimeInterval(-10), now: now))
        XCTAssertTrue(LayoutGuard.shouldReapply(lastReapply: now.addingTimeInterval(-61), now: now))
    }
}
