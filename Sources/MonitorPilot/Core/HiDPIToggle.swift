import Foundation
import CoreGraphics

enum HiDPIToggle {
    static func twin(of current: DisplayMode, in modes: [DisplayMode]) -> DisplayMode? {
        modes
            .filter {
                $0.id != current.id
                    && $0.width == current.width
                    && $0.height == current.height
                    && $0.isHiDPI != current.isHiDPI
                    && abs($0.refreshRate - current.refreshRate) < 0.5
            }
            .max { $0.pixelWidth < $1.pixelWidth }
    }
}

@MainActor
enum HiDPIToggleService {
    static func state(_ id: CGDirectDisplayID) -> (isHiDPI: Bool, twinID: Int32)? {
        let modes = ModeService.allModes(for: id)
        guard let current = modes.first(where: \.isCurrent),
              let twin = HiDPIToggle.twin(of: current, in: modes)
        else { return nil }
        return (current.isHiDPI, twin.id)
    }

    @discardableResult
    static func set(_ id: CGDirectDisplayID, hiDPI: Bool) -> Bool {
        guard let state = state(id), state.isHiDPI != hiDPI else { return false }
        return ModeService.setMode(id, modeID: state.twinID)
    }
}
