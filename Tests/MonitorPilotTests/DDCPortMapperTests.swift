import XCTest
@testable import MonitorPilot

final class DDCPortMapperTests: XCTestCase {
    let lg = DDCPortMapper.Connection(role: "DCPEXT1", productID: 0x9D5C, productName: "LG ULTRAFINE")
    let dell = DDCPortMapper.Connection(role: "DCPEXT2", productID: 0x4142, productName: "DELL P2722H")

    func testRoleFromEntryName() {
        XCTAssertEqual(DDCPortMapper.role(inEntryName: "RTBuddy(DCPEXT1)"), "DCPEXT1")
        XCTAssertEqual(DDCPortMapper.role(inEntryName: "iop-dcpext2-nub"), "DCPEXT2")
        XCTAssertEqual(DDCPortMapper.role(inEntryName: "dispext1:dcpav-service-epic:0"), nil)
        XCTAssertNil(DDCPortMapper.role(inEntryName: "DCPAVServiceProxy"))
    }

    func testModelMatchesInEitherByteOrder() {
        XCTAssertEqual(DDCPortMapper.role(forModel: 0x5C9D, name: "LG ULTRAFINE", in: [lg, dell]), "DCPEXT1")
        XCTAssertEqual(DDCPortMapper.role(forModel: 0x4241, name: "DELL P2722H", in: [lg, dell]), "DCPEXT2")
        XCTAssertEqual(DDCPortMapper.role(forModel: 0x4142, name: "x", in: [lg, dell]), "DCPEXT2")
    }

    func testNameBreaksTieAndUnknownStaysNil() {
        let twin = DDCPortMapper.Connection(role: "DCPEXT3", productID: 0x4142, productName: "DELL P2722H")
        XCTAssertNil(DDCPortMapper.role(forModel: 0x4241, name: "DELL P2722H", in: [dell, twin]), "2 iguais: falha alto")
        XCTAssertEqual(DDCPortMapper.role(forModel: 0, name: "LG ULTRAFINE", in: [lg, dell]), "DCPEXT1")
        XCTAssertNil(DDCPortMapper.role(forModel: 0, name: "Samsung", in: [lg, dell]))
    }
}
