import Foundation
import CoreGraphics
import AppKit

/// "Exibir Notch" (só telas internas): o macOS publica dois modos com a mesma
/// largura e a mesma escala, cujas alturas diferem exatamente pela faixa do
/// notch (ex.: 3024×1964 com notch vs 3024×1890 sem). Trocar de modo é o que o
/// BetterDisplay faz — o modo mais alto é o que EXIBE o notch.
enum NotchPlanner {
    /// Faixa do notch: até 8% da altura (Apple usa ~74px em 1964).
    static let maxBandRatio = 0.08

    /// Par (com notch, sem notch) do modo atual, se existir na lista.
    static func counterpart(of current: DisplayMode, in modes: [DisplayMode]) -> DisplayMode? {
        modes
            .filter {
                $0.id != current.id
                    && $0.pixelWidth == current.pixelWidth
                    && $0.pixelWidth > 0
                    && abs($0.scale - current.scale) < 0.01
                    && abs($0.refreshRate - current.refreshRate) < 0.5
                    && $0.pixelHeight != current.pixelHeight
                    && isNotchBand(current.pixelHeight, $0.pixelHeight)
            }
            .min { a, b in
                abs(a.pixelHeight - current.pixelHeight) < abs(b.pixelHeight - current.pixelHeight)
            }
    }

    static func isNotchBand(_ a: Int, _ b: Int) -> Bool {
        let tall = max(a, b), short = min(a, b)
        guard tall > 0, short > 0 else { return false }
        let band = tall - short
        return band > 0 && Double(band) <= Double(tall) * maxBandRatio
    }

    /// O modo mostra o notch? (é o mais alto do par)
    static func showsNotch(_ mode: DisplayMode, counterpart: DisplayMode) -> Bool {
        mode.pixelHeight > counterpart.pixelHeight
    }
}

@MainActor
enum NotchService {
    static func current(_ id: CGDirectDisplayID) -> (mode: DisplayMode, other: DisplayMode)? {
        let modes = ModeService.allModes(for: id)
        guard let current = modes.first(where: \.isCurrent),
              let other = NotchPlanner.counterpart(of: current, in: modes)
        else { return nil }
        return (current, other)
    }

    static func isSupported(_ d: DisplayInfo) -> Bool { d.isBuiltin && current(d.id) != nil }

    static func showsNotch(_ id: CGDirectDisplayID) -> Bool {
        guard let pair = current(id) else { return true }
        return NotchPlanner.showsNotch(pair.mode, counterpart: pair.other)
    }

    /// Alterna. Reversível: é só trocar de volta pro outro modo do par.
    @discardableResult
    static func set(_ id: CGDirectDisplayID, showNotch: Bool) -> Bool {
        guard let pair = current(id) else { return false }
        guard NotchPlanner.showsNotch(pair.mode, counterpart: pair.other) != showNotch else { return true }
        return ModeService.setMode(id, modeID: pair.other.id)
    }
}
