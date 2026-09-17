import Foundation
import CoreGraphics

/// Ajustes de cor por software via gamma table (API pública) —
/// o mesmo mecanismo do BetterDisplay para gamma/gain/temperatura/contraste.
/// Só tem efeito enquanto o app residente vive (WindowServer reseta no exit).
struct ColorAdjustments: Codable, Equatable {
    var brightness: Float = 1.0   // escala geral (dimming)
    var contrast: Float = 0.0     // -1…1 (0 = neutro)
    var temperature: Float = 0.0  // -1 (frio) … 1 (quente); 0 = neutro
    var gainR: Float = 1.0
    var gainG: Float = 1.0
    var gainB: Float = 1.0
    var gamma: Float = 1.0        // expoente extra (1 = neutro)
    var boost: Float = 1.0        // upscaling XDR: >1 empurra SDR pra faixa EDR

    static let neutral = ColorAdjustments()
    var isNeutral: Bool { self == .neutral }

    // Decode tolerante: config antiga sem `boost` continua válida.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decodeIfPresent(Float.self, forKey: .brightness) ?? 1
        contrast = try c.decodeIfPresent(Float.self, forKey: .contrast) ?? 0
        temperature = try c.decodeIfPresent(Float.self, forKey: .temperature) ?? 0
        gainR = try c.decodeIfPresent(Float.self, forKey: .gainR) ?? 1
        gainG = try c.decodeIfPresent(Float.self, forKey: .gainG) ?? 1
        gainB = try c.decodeIfPresent(Float.self, forKey: .gainB) ?? 1
        gamma = try c.decodeIfPresent(Float.self, forKey: .gamma) ?? 1
        boost = try c.decodeIfPresent(Float.self, forKey: .boost) ?? 1
    }
}

enum ColorService {
    private(set) static var applied: [CGDirectDisplayID: ColorAdjustments] = [:]
    private static var factory: [CGDirectDisplayID: (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue], n: UInt32)] = [:]

    private static func factoryTable(_ id: CGDirectDisplayID) -> (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue], n: UInt32)? {
        if let cached = factory[id] { return cached }
        let capacity: UInt32 = 256
        var count: UInt32 = 0
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = [CGGammaValue](repeating: 0, count: Int(capacity))
        var b = [CGGammaValue](repeating: 0, count: Int(capacity))
        guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count) == .success else { return nil }
        let table = (r, g, b, count)
        factory[id] = table
        return table
    }

    /// Multiplicadores RGB por temperatura (aprox. Planck simplificado: quente corta azul, frio corta vermelho).
    static func temperatureScales(_ t: Float) -> (r: Float, g: Float, b: Float) {
        let t = min(max(t, -1), 1)
        if t >= 0 { return (1, 1 - 0.15 * t, 1 - 0.45 * t) }   // quente
        return (1 + 0.35 * t, 1 + 0.10 * t, 1)                  // frio (t negativo)
    }

    /// Curva final por canal: v' = ((curva_contraste(v))^gamma) * ganho * temperatura * brilho
    static func transform(_ v: Float, adj: ColorAdjustments, channelGain: Float, tempScale: Float) -> Float {
        var x = min(max(v, 0), 1)
        if adj.contrast != 0 {
            // contraste em torno de 0.5: c>0 aumenta inclinação, c<0 achata
            let slope = adj.contrast >= 0 ? 1 + 3 * adj.contrast : 1 + adj.contrast * 0.9
            x = min(max((x - 0.5) * slope + 0.5, 0), 1)
        }
        if adj.gamma != 1 { x = pow(x, 1 / max(adj.gamma, 0.1)) }
        // boost > 1 = upscaling XDR: deixa a curva passar de 1.0 (faixa EDR).
        let ceiling = max(adj.boost, 1)
        return min(x * channelGain * tempScale * adj.brightness * adj.boost, ceiling)
    }

    @discardableResult
    static func apply(_ id: CGDirectDisplayID, _ adj: ColorAdjustments) -> Bool {
        guard let base = factoryTable(id) else { return false }
        let n = Int(base.n)
        var r = [CGGammaValue](repeating: 0, count: n)
        var g = [CGGammaValue](repeating: 0, count: n)
        var b = [CGGammaValue](repeating: 0, count: n)
        let temp = temperatureScales(adj.temperature)
        for i in 0..<n {
            r[i] = transform(base.r[i], adj: adj, channelGain: adj.gainR, tempScale: temp.r)
            g[i] = transform(base.g[i], adj: adj, channelGain: adj.gainG, tempScale: temp.g)
            b[i] = transform(base.b[i], adj: adj, channelGain: adj.gainB, tempScale: temp.b)
        }
        guard CGSetDisplayTransferByTable(id, base.n, r, g, b) == .success else { return false }
        applied[id] = adj
        return true
    }

    /// Troca de preset Apple carrega tabela de fábrica NOVA (cada preset tem a
    /// sua) e zera a atual — o cache velho vira lixo. Chame após setPreset.
    static func invalidateFactoryTable(_ id: CGDirectDisplayID) {
        factory[id] = nil
    }

    static func reset(_ id: CGDirectDisplayID) {
        if let base = factoryTable(id) {
            CGSetDisplayTransferByTable(id, base.n, base.r, base.g, base.b)
        }
        applied[id] = nil
    }

    static func resetAll() {
        CGDisplayRestoreColorSyncSettings()
        applied.removeAll()
        factory.removeAll()
    }
}
