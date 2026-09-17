import XCTest
@testable import MonitorPilot

/// Só leitura — nenhum teste liga/desliga o brilho automático do dono.
final class AmbientServiceTests: XCTestCase {
    func testUnknownDisplayIsNotSupported() {
        XCTAssertFalse(AmbientService.isSupported(0xDEAD_BEEF))
        XCTAssertNil(AmbientService.enabled(0xDEAD_BEEF))
    }

    func testAvailabilityIsConsistent() {
        // Sem os símbolos, nada é suportado; com eles, ler não pode explodir.
        if !AmbientService.isAvailable {
            XCTAssertFalse(AmbientService.isSupported(CGMainDisplayID()))
        } else {
            _ = AmbientService.enabled(CGMainDisplayID())
        }
    }
}
