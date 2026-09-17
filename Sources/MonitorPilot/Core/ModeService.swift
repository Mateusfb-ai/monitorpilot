import Foundation
import CoreGraphics

struct DisplayMode: Identifiable, Hashable {
    let id: Int32
    let width: Int
    let height: Int
    let refreshRate: Double
    let isHiDPI: Bool
    let isCurrent: Bool
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var scale: Double = 1
    /// `false` = modo que o painel do Sistema esconde (só aparece com "Mostrar todos").
    var isUserVisible: Bool = true

    var label: String {
        let hz = refreshRate > 0 ? String(format: "%.4g Hz", refreshRate) : "—"
        return "\(width)×\(height)\(isHiDPI ? " HiDPI" : "") · \(hz)"
    }
}

enum ModeService {
    static func modes(for id: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else {
            return []
        }
        let current = CGDisplayCopyDisplayMode(id)
        return all
            .filter { $0.isUsableForDesktopGUI() }
            .map { mode in
                DisplayMode(
                    id: mode.ioDisplayModeID,
                    width: mode.width,
                    height: mode.height,
                    refreshRate: mode.refreshRate,
                    isHiDPI: mode.pixelWidth > mode.width,
                    isCurrent: mode.ioDisplayModeID == current?.ioDisplayModeID,
                    pixelWidth: mode.pixelWidth,
                    pixelHeight: mode.pixelHeight,
                    scale: mode.width > 0 ? Double(mode.pixelWidth) / Double(mode.width) : 1
                )
            }
            .sorted {
                ($0.width, $0.height, $0.refreshRate) > ($1.width, $1.height, $1.refreshRate)
            }
    }

    /// Todos os modos, inclusive os que o painel do Sistema esconde
    /// (`isUserVisible == false` no MPDisplay) — é o "Mostrar todos (HiDPI)".
    /// Sem MonitorPanel disponível, cai pra lista pública.
    static func allModes(for id: CGDirectDisplayID) -> [DisplayMode] {
        let public_ = modes(for: id)
        guard let mp = PresetService.display(for: id),
              let raw = mp.value(forKey: "allModes") as? [NSObject]
        else { return public_ }
        let currentNumber = CGDisplayCopyDisplayMode(id)?.ioDisplayModeID
        let known = Set(public_.map(\.id))
        let hidden: [DisplayMode] = raw.compactMap { m in
            func int(_ k: String) -> Int { (m.value(forKey: k) as? NSNumber)?.intValue ?? 0 }
            let number = Int32(int("modeNumber"))
            guard !known.contains(number) else { return nil }
            let w = int("width"), h = int("height")
            guard w > 0, h > 0 else { return nil }
            let pw = max(int("pixelsWide"), w), ph = max(int("pixelsHigh"), h)
            return DisplayMode(
                id: number, width: w, height: h,
                refreshRate: (m.value(forKey: "refreshRate") as? NSNumber)?.doubleValue ?? 0,
                isHiDPI: pw > w, isCurrent: number == currentNumber,
                pixelWidth: pw, pixelHeight: ph,
                scale: Double(pw) / Double(w),
                isUserVisible: (m.value(forKey: "isUserVisible") as? Bool) ?? true)
        }
        return (public_ + hidden).sorted {
            ($0.width, $0.height, $0.refreshRate) > ($1.width, $1.height, $1.refreshRate)
        }
    }

    /// Lista pra UI: pública, ou completa quando o display está com "Mostrar todos".
    static func modes(for id: CGDirectDisplayID, showAll: Bool) -> [DisplayMode] {
        showAll ? allModes(for: id) : modes(for: id)
    }

    /// Escada de resoluções pro slider: tamanhos lógicos únicos, preferindo HiDPI
    /// e o maior refresh de cada tamanho, do menor pro maior.
    static func resolutionLadder(for id: CGDirectDisplayID, showAll: Bool = false) -> [DisplayMode] {
        let all = modes(for: id, showAll: showAll)
        var best: [String: DisplayMode] = [:]
        for m in all {
            let key = "\(m.width)x\(m.height)"
            if let existing = best[key] {
                let better = (m.isHiDPI && !existing.isHiDPI)
                    || (m.isHiDPI == existing.isHiDPI && m.refreshRate > existing.refreshRate)
                if better { best[key] = m }
            } else {
                best[key] = m
            }
        }
        return best.values.sorted { ($0.width, $0.height) < ($1.width, $1.height) }
    }

    /// Refreshes disponíveis pra resolução atual (mesmo WxH e mesma classe HiDPI).
    static func refreshOptions(for id: CGDirectDisplayID, width: Int, height: Int,
                               showAll: Bool = false) -> [DisplayMode] {
        modes(for: id, showAll: showAll)
            .filter { $0.width == width && $0.height == height }
            .sorted { $0.refreshRate > $1.refreshRate }
    }

    /// Largura nativa em pixels (maior pixelWidth entre os modos) — base do % de escala:
    /// 100% = metade dos pixels nativos (o "Retina padrão").
    static func nativePixelWidth(_ id: CGDirectDisplayID) -> Int {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return 0 }
        let nativeFlag: UInt32 = 0x0200_0000  // kDisplayModeNativeFlag
        if let native = all.first(where: { $0.ioFlags & nativeFlag != 0 }) {
            return native.pixelWidth
        }
        return all.map(\.pixelWidth).max() ?? 0
    }

    static func scalePercent(_ id: CGDirectDisplayID, logicalWidth: Int) -> Int? {
        let native = nativePixelWidth(id)
        guard native > 0 else { return nil }
        return Int((Double(logicalWidth) / (Double(native) / 2) * 100).rounded())
    }

    @discardableResult
    static func setMode(_ display: CGDirectDisplayID, modeID: Int32) -> Bool {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode],
              let target = all.first(where: { $0.ioDisplayModeID == modeID })
        else { return setHiddenMode(display, modeNumber: modeID) }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, display, target, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}


extension ModeService {
    /// Modo que a API pública não enxerga (escondido do painel do Sistema):
    /// vai por MPDisplay.setModeNumber: (int → int), com lock do MPDisplayMgr.
    /// Verificado nesta máquina: MP `modeNumber` == CG `ioDisplayModeID`.
    @discardableResult
    static func setHiddenMode(_ display: CGDirectDisplayID, modeNumber: Int32) -> Bool {
        guard let mp = PresetService.display(for: display) else { return false }
        let sel = NSSelectorFromString("setModeNumber:")
        guard mp.responds(to: sel), let imp = mp.method(for: sel) else { return false }
        return PresetService.withLock {
            typealias SetModeNumber = @convention(c) (AnyObject, Selector, Int32) -> Int32
            return unsafeBitCast(imp, to: SetModeNumber.self)(mp, sel, modeNumber) == 0
        }
    }

    /// O display tem modo HiDPI pra sua resolução nativa? (MPDisplay privado;
    /// sem MonitorPanel, infere pela lista pública.)
    static func hasNativeHiDPI(_ id: CGDirectDisplayID) -> Bool {
        if let mp = PresetService.display(for: id) {
            let sel = NSSelectorFromString("hasMatchingHiDPIMode:")
            if let native = mp.value(forKey: "nativeMode") as? NSObject,
               mp.responds(to: sel), let imp = mp.method(for: sel) {
                typealias HasMatching = @convention(c) (AnyObject, Selector, NSObject) -> Bool
                return unsafeBitCast(imp, to: HasMatching.self)(mp, sel, native)
            }
            if let hidpi = mp.value(forKey: "isHiDPI") as? Bool { return hidpi }
        }
        return modes(for: id).contains { $0.isHiDPI }
    }
}
