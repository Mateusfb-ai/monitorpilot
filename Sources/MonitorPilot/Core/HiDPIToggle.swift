import Foundation
import CoreGraphics

/// Display que JÁ tem HiDPI nativo: "Alta Resolução" é só alternar entre o
/// modo HiDPI e o gêmeo de mesma resolução lógica sem HiDPI (esse gêmeo
/// costuma estar escondido do painel do Sistema — vem de `allModes`).
enum HiDPIToggle {
    /// Gêmeo do modo atual com o HiDPI invertido (mesma resolução lógica e
    /// mesma taxa). Preferindo, entre vários, o de maior densidade.
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
    /// (está em HiDPI, id do modo gêmeo) — nil quando não há par pra alternar.
    static func state(_ id: CGDirectDisplayID) -> (isHiDPI: Bool, twinID: Int32)? {
        let modes = ModeService.allModes(for: id)
        guard let current = modes.first(where: \.isCurrent),
              let twin = HiDPIToggle.twin(of: current, in: modes)
        else { return nil }
        return (current.isHiDPI, twin.id)
    }

    /// Reversível: alternar de novo volta ao modo anterior.
    @discardableResult
    static func set(_ id: CGDirectDisplayID, hiDPI: Bool) -> Bool {
        guard let state = state(id), state.isHiDPI != hiDPI else { return false }
        return ModeService.setMode(id, modeID: state.twinID)
    }
}
