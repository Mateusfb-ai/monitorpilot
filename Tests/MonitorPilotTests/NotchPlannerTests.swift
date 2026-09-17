import XCTest
@testable import MonitorPilot

final class NotchPlannerTests: XCTestCase {
    private func mode(_ id: Int32, _ w: Int, _ h: Int, _ pw: Int, _ ph: Int,
                      _ hz: Double = 120, current: Bool = false) -> DisplayMode {
        DisplayMode(id: id, width: w, height: h, refreshRate: hz,
                    isHiDPI: pw > w, isCurrent: current,
                    pixelWidth: pw, pixelHeight: ph,
                    scale: w > 0 ? Double(pw) / Double(w) : 1)
    }

    private lazy var list: [DisplayMode] = [
        mode(1, 1512, 982, 3024, 1964, current: true),
        mode(2, 1512, 945, 3024, 1890),
        mode(3, 1512, 982, 3024, 1964, 60),
        mode(4, 1710, 1112, 3420, 2224),
        mode(5, 3024, 1964, 3024, 1964),
    ]

    func testFindsNotchPair() {
        let current = list[0]
        let other = NotchPlanner.counterpart(of: current, in: list)
        XCTAssertEqual(other?.id, 2)
        XCTAssertTrue(NotchPlanner.showsNotch(current, counterpart: other!))
        XCTAssertFalse(NotchPlanner.showsNotch(other!, counterpart: current))
    }

    func testNoPairForOtherWidths() {
        XCTAssertNil(NotchPlanner.counterpart(of: list[3], in: list))
    }

    func testBandLimit() {
        XCTAssertTrue(NotchPlanner.isNotchBand(1964, 1890))
        XCTAssertFalse(NotchPlanner.isNotchBand(1964, 1080))
        XCTAssertFalse(NotchPlanner.isNotchBand(1964, 1964))
        XCTAssertFalse(NotchPlanner.isNotchBand(0, 1890))
    }

    func testIgnoresDifferentRefresh() {
        let sixtyOnly = [list[0], mode(9, 1512, 945, 3024, 1890, 60)]
        XCTAssertNil(NotchPlanner.counterpart(of: sixtyOnly[0], in: sixtyOnly))
    }
}
