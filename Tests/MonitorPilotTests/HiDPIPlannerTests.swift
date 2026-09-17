import XCTest
@testable import MonitorPilot

final class HiDPIPlannerTests: XCTestCase {
    func testNativeFitsUnderCap() {
        let p = HiDPIPlanner.plan(nativeW: 3840, nativeH: 2160)
        XCTAssertEqual(p.virtualW, 3840)
        XCTAssertEqual(p.virtualH, 2160)
        XCTAssertEqual(p.logicalW, 1920)
        XCTAssertEqual(p.logicalH, 1080)
    }

    func testUltrawideUnderBaseCap() {
        let p = HiDPIPlanner.plan(nativeW: 3440, nativeH: 1440)
        XCTAssertEqual(p.virtualW, 3440)
        XCTAssertEqual(p.logicalW, 1720)
        XCTAssertEqual(p.logicalH, 720)
    }

    func testClampsToBaseCapKeepingAspect() {
        let p = HiDPIPlanner.plan(nativeW: 7680, nativeH: 2160)
        XCTAssertEqual(p.virtualW, 6144)
        XCTAssertEqual(p.virtualH, 1728)  // 2160 * 6144/7680
        XCTAssertEqual(p.logicalW, 3072)
    }

    func testProCapIsWider() {
        let p = HiDPIPlanner.plan(nativeW: 7680, nativeH: 2160, cap: HiDPIPlanner.proCap)
        XCTAssertEqual(p.virtualW, 7680)
        XCTAssertEqual(p.logicalW, 3840)
    }

    func testAlwaysEvenAndNonZero() {
        let p = HiDPIPlanner.plan(nativeW: 1367, nativeH: 769)
        XCTAssertEqual(p.virtualW % 2, 0)
        XCTAssertEqual(p.virtualH % 2, 0)
        XCTAssertEqual(p.logicalW * 2, p.virtualW)
        let zero = HiDPIPlanner.plan(nativeW: 0, nativeH: 0)
        XCTAssertEqual(zero.virtualW, 0)
    }

    func testPortraitClamp() {
        let p = HiDPIPlanner.plan(nativeW: 2160, nativeH: 7680)
        XCTAssertEqual(p.virtualH, 6144)
        XCTAssertEqual(p.virtualW, 1728)
    }

    func testSupersampleDoublesPixelsKeepsLogicalNative() {
        let p = HiDPIPlanner.plan(nativeW: 1080, nativeH: 1920, cap: HiDPIPlanner.proCap, supersample: true)
        XCTAssertEqual(p.virtualW, 2160)
        XCTAssertEqual(p.virtualH, 3840)
        XCTAssertEqual(p.logicalW, 1080)
        XCTAssertEqual(p.logicalH, 1920)
    }

    func testSupersampleClampsToCap() {
        let p = HiDPIPlanner.plan(nativeW: 3840, nativeH: 2160, cap: HiDPIPlanner.baseCap, supersample: true)
        XCTAssertEqual(p.virtualW, 6144)   // 7680 estoura o teto base
        XCTAssertEqual(p.virtualH, 3456)
        XCTAssertEqual(p.logicalW, 3072)
    }

    func testSupersampleOffIsUnchanged() {
        let a = HiDPIPlanner.plan(nativeW: 1080, nativeH: 1920)
        let b = HiDPIPlanner.plan(nativeW: 1080, nativeH: 1920, supersample: false)
        XCTAssertEqual(a.virtualW, b.virtualW); XCTAssertEqual(a.logicalH, b.logicalH)
        XCTAssertEqual(a.logicalW, 540)
    }
}
