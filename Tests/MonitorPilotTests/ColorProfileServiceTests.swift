import XCTest
@testable import MonitorPilot

final class ColorProfileServiceTests: XCTestCase {
    func testInstalledProfilesAreUniqueAndSorted() {
        let profiles = ColorProfileService.installedProfiles()
        XCTAssertEqual(Set(profiles.map(\.url)).count, profiles.count, "perfis duplicados")
        let names = profiles.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertTrue(profiles.allSatisfy { !$0.name.isEmpty })
    }
}
