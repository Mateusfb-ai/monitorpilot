import Foundation
import CoreGraphics
import ObjectiveC

/// Predefinições de tela Apple (XDR reference modes) via MonitorPanel.framework
/// privado — MPDisplayMgr / MPDisplay / MPDisplayPreset, tudo por ObjC runtime
/// com fallback: se as classes sumirem numa versão futura, a feature se desliga.
struct XDRPreset: Identifiable, Equatable {
    let index: Int
    let name: String
    let maxSDRNits: Double?
    let maxHDRNits: Double?
    let maxEDRHeadroom: Double?

    var id: Int { index }

    var detail: String? {
        guard let sdr = maxSDRNits else { return nil }
        if let hdr = maxHDRNits, hdr > sdr { return "\(Int(sdr))/\(Int(hdr)) nits" }
        return "\(Int(sdr)) nits"
    }
}

enum PresetService {
    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW)

    static var available: Bool {
        handle != nil && NSClassFromString("MPDisplayMgr") != nil
    }

    // MPDisplayMgr.init custa ~1,5s (medido) — UMA instância, criada fora da
    // main thread. Instância cacheada enxerga troca externa de preset (provado
    // ao vivo). Antes do warm-up terminar, accessors devolvem vazio/nil rápido.
    private nonisolated(unsafe) static var cachedManager: NSObject?
    private static let warmupQueue = DispatchQueue(label: "monitorpilot.preset.warmup")

    /// Chame no launch do app. Nunca na abertura do popover.
    static func warmUp(then onReady: (@Sendable () -> Void)? = nil) {
        warmupQueue.async {
            guard cachedManager == nil, available,
                  let cls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return }
            let mgr = cls.init()
            cachedManager = mgr
            onReady?()
        }
    }

    /// CLI (processo curto, sem popover): cria bloqueante.
    static func warmUpBlocking() {
        guard cachedManager == nil, available,
              let cls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return }
        cachedManager = cls.init()
    }

    static func manager() -> NSObject? { cachedManager }

    /// Executa `body` com o MPDisplayMgr travado (não briga com Ajustes do
    /// Sistema). Sem manager pronto, roda direto — o chamador já checou.
    static func withLock<T>(_ body: () -> T) -> T {
        guard let mgr = manager() else { return body() }
        let tryLock = NSSelectorFromString("tryLockAccess")
        let unlock = NSSelectorFromString("unlockAccess")
        var locked = false
        if let imp = mgr.method(for: tryLock) {
            locked = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Bool).self)(mgr, tryLock)
        }
        defer {
            if locked, let imp = mgr.method(for: unlock) {
                unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Void).self)(mgr, unlock)
            }
        }
        return body()
    }

    private static func mpDisplay(_ mgr: NSObject, _ id: CGDirectDisplayID) -> NSObject? {
        guard let displays = mgr.value(forKey: "displays") as? [NSObject] else { return nil }
        return displays.first { ($0.value(forKey: "displayID") as? UInt32) == id }
    }

    /// MPDisplay do id, se o manager já estiver pronto (warmUp/warmUpBlocking chamado).
    static func display(for id: CGDirectDisplayID) -> NSObject? {
        guard let mgr = manager() else { return nil }
        return mpDisplay(mgr, id)
    }

    // MARK: HDR ("High Dynamic Range" de Ajustes › Monitores — mesma chave KVC
    // que o painel do Sistema usa; SystemService cai pro SLS só se isso faltar).

    static func hasHDRModes(_ id: CGDirectDisplayID) -> Bool {
        guard let d = display(for: id) else { return false }
        return (d.value(forKey: "hasHDRModes") as? Bool) ?? false
    }

    static func preferHDRModes(_ id: CGDirectDisplayID) -> Bool? {
        guard let d = display(for: id) else { return nil }
        return d.value(forKey: "preferHDRModes") as? Bool
    }

    /// Ativa/desativa o mesmo toggle "High Dynamic Range" de Ajustes › Monitores.
    /// Devolve o valor relido (sucesso = bate com o pedido).
    @discardableResult
    static func setPreferHDRModes(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        guard let d = display(for: id) else { return false }
        d.setValue(on, forKey: "preferHDRModes")
        return preferHDRModes(id) == on
    }

    private static func presetInfo(_ p: NSObject, index: Int) -> XDRPreset {
        let dict = p.value(forKey: "presetDictionary") as? [String: Any]
        return XDRPreset(
            index: index,
            name: (p.value(forKey: "presetName") as? String) ?? "Preset \(index)",
            maxSDRNits: dict?["PresetMaxSDRLuminance"] as? Double,
            maxHDRNits: dict?["PresetMaxHDRLuminance"] as? Double,
            maxEDRHeadroom: dict?["PresetHostMaxPotentialEDRHeadroom"] as? Double)
    }

    static func hasPresets(_ id: CGDirectDisplayID) -> Bool {
        guard let mgr = manager(), let d = mpDisplay(mgr, id) else { return false }
        return (d.value(forKey: "hasPresets") as? Bool) ?? false
    }

    /// Presets válidos do display, na ordem do sistema.
    static func presets(for id: CGDirectDisplayID) -> [XDRPreset] {
        guard let mgr = manager(), let d = mpDisplay(mgr, id),
              (d.value(forKey: "hasPresets") as? Bool) == true,
              let list = d.value(forKey: "presets") as? [NSObject]
        else { return [] }
        return list.enumerated()
            .filter { ($0.element.value(forKey: "isValid") as? Bool) == true }
            .map { presetInfo($0.element, index: $0.offset) }
    }

    static func activePresetIndex(_ id: CGDirectDisplayID) -> Int? {
        guard let mgr = manager(), let d = mpDisplay(mgr, id),
              let active = d.value(forKey: "activePreset") as? NSObject
        else { return nil }
        return (active.value(forKey: "presetIndex") as? Int)
    }

    /// Troca o preset (com lock do MPDisplayMgr pra não brigar com os Ajustes
    /// do Sistema). O chamador deve reler headroom/brilho e reaplicar gamma
    /// depois — a troca zera a tabela de transferência.
    @discardableResult
    static func setPreset(_ id: CGDirectDisplayID, index: Int) -> Bool {
        guard let mgr = manager(), let d = mpDisplay(mgr, id),
              let list = d.value(forKey: "presets") as? [NSObject],
              list.indices.contains(index),
              (list[index].value(forKey: "isValid") as? Bool) == true
        else { return false }
        // perform() não serve pra retorno BOOL (escalar vira ponteiro → crash);
        // chamada via IMP tipado.
        let tryLock = NSSelectorFromString("tryLockAccess")
        let unlock = NSSelectorFromString("unlockAccess")
        var locked = false
        if let imp = mgr.method(for: tryLock) {
            locked = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Bool).self)(mgr, tryLock)
        }
        defer {
            if locked, let imp = mgr.method(for: unlock) {
                unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> Void).self)(mgr, unlock)
            }
        }
        _ = d.perform(NSSelectorFromString("setActivePreset:"), with: list[index])
        return true
    }
}
