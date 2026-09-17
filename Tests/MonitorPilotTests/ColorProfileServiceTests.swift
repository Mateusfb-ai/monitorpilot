import XCTest
@testable import MonitorPilot

/// Só leitura (ColorSync público) — nenhum teste troca perfil do display.
final class ColorProfileServiceTests: XCTestCase {
    func testInstalledProfilesAreUniqueAndSorted() {
        let profiles = ColorProfileService.installedProfiles()
        XCTAssertEqual(Set(profiles.map(\.url)).count, profiles.count, "perfis duplicados")
        let names = profiles.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertTrue(profiles.allSatisfy { !$0.name.isEmpty })
    }
}
