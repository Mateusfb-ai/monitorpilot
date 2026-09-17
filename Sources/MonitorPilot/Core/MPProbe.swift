import Foundation
import CoreGraphics
import ObjectiveC

enum MPProbe {
    private static let selectors = [
        "setOrientation:", "orientation", "canChangeOrientation",
        "setMode:", "setModeNumber:", "isHiDPI", "hasMatchingHiDPIMode:",
        "isMirrored", "isMirrorMaster", "mirrorMasterDisplayID", "setMirrorMaster:",
        "displayBounds", "hardwareBounds", "allModes", "currentMode", "nativeMode",
    ]
    private static let mgrSelectors = [
        "lockAccess", "unlockAccess", "tryLockAccess",
        "setMirrorMaster:useBestMode:", "stopMirroringForDisplay:", "mirrorSetForDisplay:",
    ]

    static func run() -> Int32 {
        PresetService.warmUpBlocking()
        guard let mgrClass = NSClassFromString("MPDisplayMgr") else {
            print("MonitorPanel indisponível"); return 1
        }
        print("== MPDisplayMgr ==")
        for s in mgrSelectors { print("  \(s): \(encoding(mgrClass, s))") }
        for d in DisplayManager.onlineDisplays() {
            guard let mp = PresetService.display(for: d.id) else {
                print("\n== \(d.name): sem MPDisplay =="); continue
            }
            print("\n== \(d.name) (id \(d.id)) ==")
            for s in selectors { print("  \(s): \(encoding(type(of: mp), s))") }
            let cur = CGDisplayCopyDisplayMode(d.id)
            let mpCur = mp.value(forKey: "currentMode") as? NSObject
            print("  CG ioDisplayModeID: \(cur?.ioDisplayModeID ?? -1)")
            print("  MP modeNumber:      \(mpCur?.value(forKey: "modeNumber") ?? "?")")
            print("  MP isHiDPI: \(mp.value(forKey: "isHiDPI") ?? "?") · canChangeOrientation: \(mp.value(forKey: "canChangeOrientation") ?? "?") · orientation: \(mp.value(forKey: "orientation") ?? "?")")
            print("  perfil ICC atual: \(ColorProfileService.currentProfile(d.id)?.name ?? "?") · fábrica: \(ColorProfileService.isFactory(d.id))")
            print("  brilho automático: disponível=\(AmbientService.isAvailable) suportado=\(AmbientService.isSupported(d.id)) ativo=\(AmbientService.enabled(d.id).map(String.init) ?? "?")")
            let all = (mp.value(forKey: "allModes") as? [NSObject]) ?? []
            print("  allModes: \(all.count) (CG usáveis: \(ModeService.modes(for: d.id).count))")
            for m in all.prefix(400) {
                let vis = (m.value(forKey: "isUserVisible") as? Bool) ?? false
                guard !vis else { continue }
                print("    oculto: \(desc(m))")
            }
        }
        let profiles = ColorProfileService.installedProfiles()
        print("\nperfis de monitor instalados: \(profiles.count) — \(profiles.prefix(6).map(\.name).joined(separator: ", "))")
        return 0
    }

    private static func desc(_ m: NSObject) -> String {
        func v(_ k: String) -> String { "\(m.value(forKey: k) ?? "?")" }
        return "\(v("width"))x\(v("height")) px \(v("pixelsWide"))x\(v("pixelsHigh")) scale \(v("scale")) \(v("refreshRate"))Hz hidpi=\(v("isHiDPI")) native=\(v("isNativeMode")) modeNumber=\(v("modeNumber"))"
    }

    private static func encoding(_ cls: AnyClass, _ name: String) -> String {
        let sel = NSSelectorFromString(name)
        guard let m = class_getInstanceMethod(cls, sel),
              let e = method_getTypeEncoding(m) else { return "AUSENTE" }
        return String(cString: e)
    }
}
