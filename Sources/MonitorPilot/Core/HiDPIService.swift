import Foundation
import CoreGraphics
import AppKit

/// "Ativar HiDPI" pra display sem modo HiDPI nativo: cria uma tela virtual do
/// tamanho de pixels nativo do físico, coloca a virtual em 2× e espelha o
/// físico nela. Reversível: guarda o modo anterior e restaura no desligar.
@MainActor
enum HiDPIService {
    /// Telas virtuais criadas pra HiDPI, por displayID físico.
    private(set) static var active: [CGDirectDisplayID: VirtualScreen] = [:]

    static var isAvailable: Bool { VirtualDisplayService.isAvailable }

    static func isActive(_ id: CGDirectDisplayID) -> Bool { active[id] != nil }

    /// Precisa do caminho virtual? (não tem HiDPI nativo pro modo nativo)
    static func needsVirtual(_ id: CGDirectDisplayID) -> Bool {
        !ModeService.hasNativeHiDPI(id)
    }

    /// Liga. Devolve o modeID que o físico tinha antes (pra persistir), ou nil se falhou.
    @discardableResult
    static func enable(_ id: CGDirectDisplayID, name: String, supersample: Bool = false) async -> Int32? {
        guard active[id] == nil else { return nil }
        let previousMode = CGDisplayCopyDisplayMode(id)?.ioDisplayModeID
        let nativeW = ModeService.nativePixelWidth(id)
        let nativeH = nativePixelHeight(id)
        let plan = HiDPIPlanner.plan(nativeW: nativeW, nativeH: nativeH, cap: HiDPIPlanner.machineCap,
                                     supersample: supersample)
        guard plan.virtualW > 0 else { return nil }

        guard let screen = VirtualDisplayService.shared.create(
            name: supersample ? "\(name) Nítido 2×" : "\(name) HiDPI",
            pixelModes: ladder(plan.virtualW, plan.virtualH),
            maxPixelsWide: plan.virtualW, maxPixelsHigh: plan.virtualH, hiDPI: true)
        else { return nil }

        // A tela virtual entra no layout de forma assíncrona — espera aparecer.
        guard let virtualID = await waitForDisplayID(screen) else {
            VirtualDisplayService.shared.destroy(screen)
            return nil
        }

        // Físico espelha a virtual (a virtual é a master, ela é quem tem o HiDPI).
        guard SystemService.setMirror(id, of: virtualID) else {
            VirtualDisplayService.shared.destroy(screen)
            if let previousMode { ModeService.setMode(id, modeID: previousMode) }
            return nil
        }

        // O modo é escolhido no FÍSICO, depois do espelho — não na virtual.
        // Sonda de 12/set (Dell 1080×1920, M4 Pro): vista de dentro do próprio
        // processo a virtual devolve lista de modos VAZIA, e escolher nela
        // deixava o espelho casar em 1× (4K vertical com texto minúsculo).
        // Depois de espelhar, o físico ganha o gêmeo HiDPI (lógica = plan.logical,
        // pixels = plan.virtual): é ele que a gente seta e confere.
        let previousHz = CGDisplayCopyDisplayMode(id)?.refreshRate ?? 60
        let ok = await applyMirroredMode(id, logicalW: plan.logicalW, pixelW: plan.virtualW, preferHz: previousHz)
        if !ok {
            if ProcessInfo.processInfo.environment["MONITORPILOT_DEBUG"] != nil {
                FileHandle.standardError.write("[hidpi] físico \(id) não expôs \(plan.logicalW)@\(plan.virtualW)px — desfazendo\n".data(using: .utf8)!)
            }
            SystemService.setMirror(id, of: nil)
            VirtualDisplayService.shared.destroy(screen)
            if let previousMode { ModeService.setMode(id, modeID: previousMode) }
            return nil
        }
        active[id] = screen
        return previousMode
    }

    /// Espera o gêmeo HiDPI aparecer na lista do físico (o WindowServer
    /// reconfigura de forma assíncrona) e aplica. Devolve `true` se o modo
    /// atual do físico ficou com (largura lógica, largura em pixels) pedidas.
    private static func applyMirroredMode(_ id: CGDirectDisplayID, logicalW: Int, pixelW: Int, preferHz: Double) async -> Bool {
        for _ in 0..<24 {   // ~6 s
            if let cur = CGDisplayCopyDisplayMode(id), cur.width == logicalW, cur.pixelWidth == pixelW { return true }
            // gêmeo HiDPI com a MESMA taxa de antes (o dono usava 60 Hz; o 1º da lista era 75)
            let twins = ModeService.modes(for: id).filter { $0.width == logicalW && $0.pixelWidth == pixelW }
            if let target = twins.min(by: { abs($0.refreshRate - preferHz) < abs($1.refreshRate - preferHz) }) {
                _ = ModeService.setMode(id, modeID: target.id)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if let cur = CGDisplayCopyDisplayMode(id) { return cur.width == logicalW && cur.pixelWidth == pixelW }
        return false
    }

    /// Desliga: desespelha, restaura o modo anterior, destrói a virtual.
    static func disable(_ id: CGDirectDisplayID, restoreModeID: Int32?) {
        SystemService.setMirror(id, of: nil)
        if let screen = active.removeValue(forKey: id) {
            VirtualDisplayService.shared.destroy(screen)
        }
        if let restoreModeID { ModeService.setMode(id, modeID: restoreModeID) }
    }

    /// Desliga tudo (chamado no encerramento do app, ANTES de destruir telas
    /// virtuais — senão o físico fica órfão no modo que o macOS escolher).
    static func disableAll(restore: (CGDirectDisplayID) -> Int32?) {
        for id in Array(active.keys) { disable(id, restoreModeID: restore(id)) }
    }

    /// Resolução lógica que o modo "Nítido 2×" entrega neste display (pra rótulo).
    static func sharpLogicalSize(_ id: CGDirectDisplayID) -> (Int, Int) {
        let p = HiDPIPlanner.plan(nativeW: ModeService.nativePixelWidth(id), nativeH: nativePixelHeight(id),
                                  cap: HiDPIPlanner.machineCap, supersample: true)
        return (p.logicalW, p.logicalH)
    }

    // MARK: internos

    /// Escada de modos da virtual, em pixels (todos 2× → lógica = metade).
    static func ladder(_ w: Int, _ h: Int) -> [(Int, Int)] {
        [1.0, 0.875, 0.75, 0.625, 0.5]
            .map { f in (even(Double(w) * f), even(Double(h) * f)) }
            .filter { $0.0 >= 1280 }
    }

    private static func even(_ v: Double) -> Int { max(2, Int(v.rounded(.down)) & ~1) }

    static func nativePixelHeight(_ id: CGDirectDisplayID) -> Int {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return 0 }
        let nativeFlag: UInt32 = 0x0200_0000
        if let native = all.first(where: { $0.ioFlags & nativeFlag != 0 }) { return native.pixelHeight }
        return all.map(\.pixelHeight).max() ?? 0
    }

    private static func waitForDisplayID(_ screen: VirtualScreen) async -> CGDirectDisplayID? {
        for _ in 0..<20 {
            if let vid = screen.displayID,
               DisplayManager.onlineDisplays().contains(where: { $0.id == vid }) {
                return vid
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
