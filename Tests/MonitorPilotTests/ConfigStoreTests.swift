import XCTest
@testable import MonitorPilot

/// Config antiga (sem os campos novos) tem que decodificar com defaults —
/// se falhar, o load() cai pra AppConfig() e o próximo save() apaga tudo.
final class ConfigStoreTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDisplayConfigFromEmptyObject() throws {
        let c = try decode("{}", as: DisplayConfig.self)
        XCTAssertFalse(c.showAllModes)
        XCTAssertFalse(c.hiDPIVirtual)
        XCTAssertNil(c.previousModeID)
        XCTAssertNil(c.hdr)
        XCTAssertEqual(c.combinedSwitchpoint, 0.5)
    }

    func testDisplayConfigFromLegacyShape() throws {
        let c = try decode(
            #"{"upscalingEnabled":true,"maxBoostPercent":180,"hdr":true}"#, as: DisplayConfig.self)
        XCTAssertTrue(c.upscalingEnabled)
        XCTAssertEqual(c.maxBoostPercent, 180)
        XCTAssertEqual(c.hdr, true)
        XCTAssertFalse(c.showAllModes)
    }

    func testAppConfigFromEmptyObject() throws {
        let c = try decode("{}", as: AppConfig.self)
        XCTAssertTrue(c.displays.isEmpty)
        XCTAssertTrue(c.restoreOnLaunch)
        XCTAssertTrue(c.hotkeysEnabled)
    }

    func testRoundTripKeepsNewFields() throws {
        var c = DisplayConfig()
        c.showAllModes = true
        c.hiDPIVirtual = true
        c.previousModeID = 887
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(DisplayConfig.self, from: data)
        XCTAssertTrue(back.showAllModes)
        XCTAssertTrue(back.hiDPIVirtual)
        XCTAssertEqual(back.previousModeID, 887)
    }
}
