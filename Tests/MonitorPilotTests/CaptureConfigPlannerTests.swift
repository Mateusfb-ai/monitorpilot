import XCTest
import CoreGraphics
@testable import MonitorPilot

final class CaptureConfigPlannerTests: XCTestCase {
    func testScaleOneKeepsPixels() {
        let s = CaptureConfigPlanner.size(forPixels: CGSize(width: 1920, height: 1080), scale: 1)
        XCTAssertEqual(s.width, 1920)
        XCTAssertEqual(s.height, 1080)
    }

    func testScaleDown() {
        let s = CaptureConfigPlanner.size(forPixels: CGSize(width: 3840, height: 2160), scale: 0.5)
        XCTAssertEqual(s.width, 1920)
        XCTAssertEqual(s.height, 1080)
    }

    func testClampsToMaxKeepingAspect() {
        let s = CaptureConfigPlanner.size(forPixels: CGSize(width: 7680, height: 2160), scale: 1)
        XCTAssertEqual(s.width, 4096)
        XCTAssertEqual(s.height, 1152)  // 2160 * 4096/7680
    }

    func testAlwaysEvenAndNonZero() {
        let s = CaptureConfigPlanner.size(forPixels: CGSize(width: 1367, height: 769), scale: 1)
        XCTAssertEqual(s.width % 2, 0)
        XCTAssertEqual(s.height % 2, 0)
        let tiny = CaptureConfigPlanner.size(forPixels: CGSize(width: 10, height: 10), scale: 0.01)
        XCTAssertGreaterThanOrEqual(tiny.width, 2)
        XCTAssertGreaterThanOrEqual(tiny.height, 2)
    }

    func testCropFullScreen() {
        let r = CaptureConfigPlanner.cropRect(normalized: CGRect(x: 0, y: 0, width: 1, height: 1),
                                              inPixels: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testCropCenterQuarter() {
        let r = CaptureConfigPlanner.cropRect(normalized: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                              inPixels: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(r, CGRect(x: 480, y: 270, width: 960, height: 540))
    }

    func testCropClampsInsideBounds() {
        let r = CaptureConfigPlanner.cropRect(normalized: CGRect(x: 0.8, y: 0.9, width: 1, height: 1),
                                              inPixels: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(r.maxX, 1000, accuracy: 1)
        XCTAssertEqual(r.maxY, 1000, accuracy: 1)
        XCTAssertGreaterThan(r.width, 0)
    }

    func testCropNegativeBecomesValid() {
        let r = CaptureConfigPlanner.cropRect(normalized: CGRect(x: -1, y: -1, width: 0, height: 0),
                                              inPixels: CGSize(width: 800, height: 600))
        XCTAssertEqual(r.origin, .zero)
        XCTAssertGreaterThanOrEqual(r.width, 2)
        XCTAssertGreaterThanOrEqual(r.height, 2)
    }
}

final class PIPConfigCodingTests: XCTestCase {
    func testRoundTrip() throws {
        var c = PIPConfig()
        c.sourceDisplayKey = "1:2:3"
        c.frame = CGRect(x: 10, y: 20, width: 640, height: 360)
        c.alpha = 0.6
        c.clickThrough = true
        c.autoStart = true
        c.crop = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(PIPConfig.self, from: data)
        XCTAssertEqual(back.sourceDisplayKey, "1:2:3")
        XCTAssertEqual(back.frame, c.frame)
        XCTAssertEqual(back.alpha, 0.6)
        XCTAssertTrue(back.clickThrough)
        XCTAssertTrue(back.autoStart)
        XCTAssertEqual(back.crop, c.crop)
    }

    /// Config antigo (sem a chave `pip`) precisa continuar decodificando.
    func testLegacyDisplayConfigWithoutPIP() throws {
        let json = Data(#"{"upscalingEnabled":true}"#.utf8)
        let dc = try JSONDecoder().decode(DisplayConfig.self, from: json)
        XCTAssertTrue(dc.upscalingEnabled)
        XCTAssertNil(dc.pip)
    }
}
