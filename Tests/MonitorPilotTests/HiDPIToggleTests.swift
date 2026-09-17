import XCTest
@testable import MonitorPilot

final class HiDPIToggleTests: XCTestCase {
    private func mode(_ id: Int32, _ w: Int, _ h: Int, _ pw: Int, _ ph: Int,
                      _ hz: Double = 60, current: Bool = false) -> DisplayMode {
        DisplayMode(id: id, width: w, height: h, refreshRate: hz,
                    isHiDPI: pw > w, isCurrent: current,
                    pixelWidth: pw, pixelHeight: ph, scale: Double(pw) / Double(w))
    }

    func testFindsNonHiDPITwin() {
        let hidpi = mode(1, 2560, 1440, 5120, 2880, current: true)
        let list = [hidpi, mode(2, 2560, 1440, 2560, 1440), mode(3, 1920, 1080, 1920, 1080)]
        XCTAssertEqual(HiDPIToggle.twin(of: hidpi, in: list)?.id, 2)
    }

    func testFindsHiDPITwinFromLowRes() {
        let plain = mode(2, 2560, 1440, 2560, 1440, current: true)
        let list = [mode(1, 2560, 1440, 5120, 2880), plain]
        XCTAssertEqual(HiDPIToggle.twin(of: plain, in: list)?.id, 1)
    }

    func testNoTwinWhenRefreshDiffers() {
        let hidpi = mode(1, 2560, 1440, 5120, 2880, 120, current: true)
        XCTAssertNil(HiDPIToggle.twin(of: hidpi, in: [hidpi, mode(2, 2560, 1440, 2560, 1440, 60)]))
    }

    func testPrefersDensestTwin() {
        let plain = mode(9, 1920, 1080, 1920, 1080, current: true)
        let list = [plain, mode(1, 1920, 1080, 3840, 2160), mode(2, 1920, 1080, 2880, 1620)]
        XCTAssertEqual(HiDPIToggle.twin(of: plain, in: list)?.id, 1)
    }
}
