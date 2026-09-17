import Foundation
import CoreGraphics

/// Brilho em três camadas, como no BetterDisplay:
/// - hardware Apple (DisplayServices, privado) para tela interna/displays Apple
/// - hardware DDC (via DDCService) para monitores externos
/// - software (gamma table, público) para qualquer display
enum BrightnessService {
    // MARK: Hardware (Apple)

    static func canChangeHardware(_ id: CGDirectDisplayID) -> Bool {
        PrivateAPI.dsCanChangeBrightness?(id) ?? false
    }

    static func hardwareBrightness(_ id: CGDirectDisplayID) -> Float? {
        guard let get = PrivateAPI.dsGetBrightness else { return nil }
        var value: Float = 0
        guard get(id, &value) == 0 else { return nil }
        return value
    }

    @discardableResult
    static func setHardwareBrightness(_ id: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let set = PrivateAPI.dsSetBrightness else { return false }
        return set(id, min(max(value, 0), 1)) == 0
    }

    // MARK: Software (delegado ao ColorService — dono único da gamma table)

    static func softwareBrightness(_ id: CGDirectDisplayID) -> Float {
        ColorService.applied[id]?.brightness ?? 1.0
    }

    /// True se o display tem algum caminho de brilho por HARDWARE (Apple ou DDC).
    /// Sem hardware, brilho vira gamma — que só sobrevive em processo residente.
    static func hasHardwarePath(_ id: CGDirectDisplayID) -> Bool {
        canChangeHardware(id) || DDCService.read(id, vcp: .brightness) != nil
    }

    // MARK: Combinado (o que a UI usa)

    /// Melhor método disponível para o display, na ordem: Apple hardware → DDC → software.
    static func brightness(_ id: CGDirectDisplayID) -> Float {
        if let hw = hardwareBrightness(id) { return hw }
        if let ddc = DDCService.read(id, vcp: .brightness) {
            return Float(ddc.current) / Float(max(ddc.max, 1))
        }
        return softwareBrightness(id)
    }

    @discardableResult
    static func setBrightness(_ id: CGDirectDisplayID, _ value: Float) -> Bool {
        let v = min(max(value, 0), 1)
        if canChangeHardware(id), setHardwareBrightness(id, v) { return true }
        // Escala pelo max real reportado pelo monitor (nem todo monitor usa 0–100).
        let max = DDCService.maxValue(id, vcp: .brightness) ?? 100
        if DDCService.write(id, vcp: .brightness, value: UInt16(v * Float(max))) {
            return true
        }
        var adj = ColorService.applied[id] ?? .neutral
        adj.brightness = v
        return ColorService.apply(id, adj)
    }

    // MARK: Brilho combinado (dimming software + hardware + upscaling XDR num slider só)

    /// Faixa do slider combinado: 0…(1+headroom extra quando upscaling ativo).
    /// Mapa (switchpoint padrão 0.5, como no BetterDisplay):
    ///   0…sw       → hardware no mínimo, dimming software 0…1
    ///   sw…1       → software neutro, hardware 0…1
    ///   1…máx      → hardware no teto, boost XDR 1…headroom
    static func combinedMax(_ id: CGDirectDisplayID, upscalingOn: Bool) -> Float {
        guard upscalingOn else { return 1 }
        let headroom = UpscalingService.currentHeadroom(id)
        return headroom > 1.01 ? 1 + (headroom - 1) : 1
    }

    static func combined(_ id: CGDirectDisplayID, switchpoint: Float = 0.5) -> Float {
        let adj = ColorService.applied[id] ?? .neutral
        if adj.boost > 1.001 { return 1 + (adj.boost - 1) }
        let hw = hardwareBrightness(id) ?? {
            if let r = DDCService.read(id, vcp: .brightness) { return Float(r.current) / Float(max(r.max, 1)) }
            return 1
        }()
        if adj.brightness < 0.999 { return adj.brightness * switchpoint }
        return switchpoint + hw * (1 - switchpoint)
    }

    @discardableResult
    static func setCombined(_ id: CGDirectDisplayID, _ value: Float, switchpoint: Float = 0.5,
                            minHardware: Float = 0.05) -> Bool {
        var adj = ColorService.applied[id] ?? .neutral
        if value > 1 {
            // região XDR: hardware no teto + boost na gamma
            _ = setHardwareLevel(id, 1)
            adj.brightness = 1
            adj.boost = value
            return ColorService.apply(id, adj)
        }
        if adj.boost > 1 { adj.boost = 1 }
        let floorHW = min(max(minHardware, 0), 0.5)
        if value >= switchpoint {
            // região hardware: piso…teto (0 absoluto apagaria o backlight)
            adj.brightness = 1
            ColorService.apply(id, adj)
            let t = (value - switchpoint) / (1 - switchpoint)
            return setHardwareLevel(id, floorHW + t * (1 - floorHW))
        }
        // região dimming software (hardware fica no piso, nunca em zero)
        _ = setHardwareLevel(id, floorHW)
        adj.brightness = max(value / switchpoint, 0)
        return ColorService.apply(id, adj)
    }

    private static func setHardwareLevel(_ id: CGDirectDisplayID, _ v: Float) -> Bool {
        if canChangeHardware(id) { return setHardwareBrightness(id, v) }
        let max = DDCService.maxValue(id, vcp: .brightness) ?? 100
        return DDCService.write(id, vcp: .brightness, value: UInt16(min(Swift.max(v, 0), 1) * Float(max)))
    }
}
