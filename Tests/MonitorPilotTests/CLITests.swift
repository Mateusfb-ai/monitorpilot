import XCTest
@testable import MonitorPilot

final class CLITests: XCTestCase {
    func testParseLevel() {
        XCTAssertEqual(CLI.parseLevel("0.8"), 0.8)
        XCTAssertEqual(CLI.parseLevel("80%"), 0.8)
        XCTAssertEqual(CLI.parseLevel("80"), 0.8)
        XCTAssertEqual(CLI.parseLevel("1"), 1.0)
        XCTAssertEqual(CLI.parseLevel("0"), 0.0)
        XCTAssertEqual(CLI.parseLevel("150%"), 1.0)
        XCTAssertNil(CLI.parseLevel("abc"))
        XCTAssertNil(CLI.parseLevel(nil))
    }

    func testParseCommands() {
        let set = CLI.parse(["set", "brightness", "0.8", "LG"])
        XCTAssertEqual(set?.operation, "set")
        XCTAssertEqual(set?.feature, "brightness")
        XCTAssertEqual(set?.value, "0.8")
        XCTAssertEqual(set?.display, "LG")

        let get = CLI.parse(["get", "brightness"])
        XCTAssertEqual(get?.operation, "get")
        XCTAssertNil(get?.display)

        let ddc = CLI.parse(["ddc", "set", "brightness", "70", "DELL"])
        XCTAssertEqual(ddc?.operation, "ddc-set")
        XCTAssertEqual(ddc?.value, "70")
        XCTAssertEqual(ddc?.display, "DELL")

        XCTAssertNil(CLI.parse([]))
        XCTAssertNil(CLI.parse(["set", "brightness"]))
    }

    func testDDCChecksum() {
        let packet: [UInt8] = [0x84, 0x03, 0x10, 0x00, 0x32, 0x00]
        let chk = DDCService.checksum(0x6E ^ 0x51, packet, upTo: 5)
        XCTAssertEqual(chk, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32)
    }

    func testParsePIPAndStream() {
        let pip = CLI.parse(["pip", "LG", "--of", "Tela interna"])
        XCTAssertEqual(pip?.operation, "pip")
        XCTAssertEqual(pip?.feature, "LG")
        XCTAssertEqual(pip?.display, "Tela interna")

        let pipNoAnchor = CLI.parse(["pip", "LG"])
        XCTAssertEqual(pipNoAnchor?.feature, "LG")
        XCTAssertNil(pipNoAnchor?.display)

        XCTAssertEqual(CLI.parse(["pip", "off"])?.feature, "off")

        let stream = CLI.parse(["stream", "LG", "--to", "virtual"])
        XCTAssertEqual(stream?.operation, "stream")
        XCTAssertEqual(stream?.feature, "LG")
        XCTAssertEqual(stream?.value, "virtual")

        XCTAssertEqual(CLI.parse(["stream", "off"])?.feature, "off")
        XCTAssertNil(CLI.parse(["pip"]))
        XCTAssertNil(CLI.parse(["stream"]))
    }

    func testOffNotificationNames() {
        XCTAssertEqual(CLI.offNotification("pip").rawValue, "app.monitorpilot.pip.off")
        XCTAssertEqual(CLI.offNotification("stream").rawValue, "app.monitorpilot.stream.off")
    }
}
