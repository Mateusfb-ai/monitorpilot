import SwiftUI

@main
struct Entry {
    static var windowMode = false
    static var popoverPreview = false

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--window"] || args == ["--popover-preview"] {
            windowMode = true
            popoverPreview = args == ["--popover-preview"]
            MonitorPilotApp.main()
            return
        }
        if args == ["mp-probe"] {
            exit(MPProbe.run())
        }
        if args == ["virtual-test"] {
            let before = DisplayManager.onlineDisplays().count
            guard let screen = MainActor.assumeIsolated({
                VirtualDisplayService.shared.create(name: "MonitorPilot Teste", aspectWidth: 16, aspectHeight: 9)
            }) else {
                print("criação falhou (classes CGVirtualDisplay indisponíveis?)")
                exit(1)
            }
            Thread.sleep(forTimeInterval: 2)
            let during = DisplayManager.onlineDisplays()
            print("antes: \(before) displays · durante: \(during.count) — \(during.map(\.name).joined(separator: ", "))")
            print("displayID virtual: \(MainActor.assumeIsolated { screen.displayID.map(String.init) ?? "?" })")
            MainActor.assumeIsolated { VirtualDisplayService.shared.destroyAll() }
            Thread.sleep(forTimeInterval: 1)
            print("depois de destruir: \(DisplayManager.onlineDisplays().count) displays")
            exit(during.count == before + 1 ? 0 : 1)
        }
        if args == ["upscale-test"] {
            _ = NSApplication.shared
            let id = CGMainDisplayID()
            print("potencial: \(UpscalingService.potentialHeadroom(id))× · atual (antes): \(UpscalingService.currentHeadroom(id))×")
            MainActor.assumeIsolated { UpscalingService.shared.setEDRPipeline(active: true) }
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            let headroom = UpscalingService.currentHeadroom(id)
            print("atual (pipeline EDR ativo): \(headroom)×")
            var adj = ColorAdjustments(); adj.boost = 1.25
            let applied = ColorService.apply(id, adj)
            var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r; var n: UInt32 = 0
            CGGetDisplayTransferByTable(id, 256, &r, &g, &b, &n)
            print("apply(boost 1.25): \(applied) · gamma máx readback: \(r[Int(n)-1])")
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            ColorService.reset(id)
            MainActor.assumeIsolated { UpscalingService.shared.setEDRPipeline(active: false) }
            print(applied && r[Int(n)-1] > 1.01 ? "UPSCALING OK (tabela aceita >1.0)" : "tabela clampou em 1.0 — método precisa de ajuste")
            exit(0)
        }
        if args.first == "edr-lg-test" {
            _ = NSApplication.shared
            guard let lg = DisplayManager.onlineDisplays().first(where: { !$0.isBuiltin }) else {
                print("sem display externo"); exit(1)
            }
            let id = lg.id
            print("[0] potencial \(UpscalingService.potentialHeadroom(id))× · atual \(UpscalingService.currentHeadroom(id))×")
            MainActor.assumeIsolated { UpscalingService.shared.setEDRPipeline(active: true) }
            RunLoop.main.run(until: Date().addingTimeInterval(3))
            print("[1] com ativador EDR: atual \(UpscalingService.currentHeadroom(id))×")
            print("    SLS hdr suportado: \(SystemService.hdrSupported(id)) · ativo: \(SystemService.hdrEnabled(id))")
            let forced = SystemService.setHDR(id, true)
            RunLoop.main.run(until: Date().addingTimeInterval(3))
            print("[2] após SLSDisplaySetHDRModeEnabled(true) → \(forced): atual \(UpscalingService.currentHeadroom(id))× · hdr ativo: \(SystemService.hdrEnabled(id))")
            var adj = ColorAdjustments(); adj.boost = 1.3
            let ok = ColorService.apply(id, adj)
            var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r; var n: UInt32 = 0
            CGGetDisplayTransferByTable(id, 256, &r, &g, &b, &n)
            print("[3] boost 1.3 no LG: apply=\(ok) · readback máx=\(r[Int(n)-1])")
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            ColorService.reset(id)
            if forced { _ = SystemService.setHDR(id, false) }
            MainActor.assumeIsolated { UpscalingService.shared.setEDRPipeline(active: false) }
            print("estado restaurado")
            exit(0)
        }
        if args.first == "forcehdr-test" {
            _ = NSApplication.shared
            guard let lg = DisplayManager.onlineDisplays().first(where: { !$0.isBuiltin }) else {
                print("sem display externo"); exit(1)
            }
            let id = lg.id
            let originalMode = ModeService.modes(for: id).first(where: \.isCurrent)
            print("modo atual: \(originalMode?.label ?? "?") · HDR suportado: \(SystemService.hdrSupported(id)) · headroom atual: \(UpscalingService.currentHeadroom(id))×")
            for hz in [30.0, 50.0] {
                guard let target = ModeService.modes(for: id).first(where: {
                    $0.width == 3840 && $0.height == 2160 && abs($0.refreshRate - hz) < 0.5
                }) else { continue }
                print("→ mudando pra \(target.label)…")
                guard ModeService.setMode(id, modeID: target.id) else { print("  set falhou"); continue }
                RunLoop.main.run(until: Date().addingTimeInterval(3))
                let sup = SystemService.hdrSupported(id)
                print("  HDR suportado agora: \(sup)")
                if sup {
                    let ok = SystemService.setHDR(id, true)
                    RunLoop.main.run(until: Date().addingTimeInterval(3))
                    print("  setHDR(true)=\(ok) · ativo: \(SystemService.hdrEnabled(id)) · headroom: \(UpscalingService.currentHeadroom(id))× · potencial: \(UpscalingService.potentialHeadroom(id))×")
                    _ = SystemService.setHDR(id, false)
                    RunLoop.main.run(until: Date().addingTimeInterval(1))
                    if ok { break }
                }
            }
            if let orig = originalMode {
                print("← restaurando \(orig.label)")
                _ = ModeService.setMode(id, modeID: orig.id)
                RunLoop.main.run(until: Date().addingTimeInterval(2))
            }
            print("fim — estado restaurado")
            exit(0)
        }
        if args == ["combined-test"] {
            let id = CGMainDisplayID()
            let original = BrightnessService.hardwareBrightness(id) ?? 1
            _ = BrightnessService.setCombined(id, 0.3)
            let floorHW = BrightnessService.hardwareBrightness(id) ?? -1
            print("combinado 0.3 → hardware em \(floorHW) (esperado ≥0.04, nunca 0)")
            _ = BrightnessService.setCombined(id, 1.2)
            var cfg = AppConfig()
            var dc = DisplayConfig()
            dc.color = ColorService.applied[id] ?? .neutral
            cfg.displays["test"] = dc
            ConfigStore.save(cfg)
            let boost = ConfigStore.load().displays["test"]?.color.boost ?? -1
            print("boost persistido e relido: \(boost) (esperado 1.2)")
            ColorService.reset(id)
            _ = BrightnessService.setHardwareBrightness(id, original)
            print(floorHW >= 0.04 && abs(boost - 1.2) < 0.001 ? "COMBINED OK" : "FALHOU")
            exit(floorHW >= 0.04 && abs(boost - 1.2) < 0.001 ? 0 : 1)
        }
        if !args.isEmpty {
            exit(CLI.run(args))
        }
        MonitorPilotApp.main()
    }
}

struct MonitorPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = DisplayStore()

    var body: some Scene {
        WindowGroup("MonitorPilot", id: "main") {
            if Entry.popoverPreview {
                MenuView(store: store).fixedSize()
            } else if Entry.windowMode {
                SettingsRootView(store: store, virtuals: VirtualDisplayService.shared)
            }
        }
        .defaultPosition(.center)

        MenuBarExtra {
            MenuView(store: store)
        } label: {
            Image(systemName: "sun.max.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var teardownHiDPI: (() -> Void)?
    private var previewWindow: NSWindow?

    private static var termSource: DispatchSourceSignal?
    private static func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { NSApplication.shared.terminate(nil) }
        src.resume()
        termSource = src
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.installSignalHandlers()
        if Entry.windowMode {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate()
            if Entry.popoverPreview {
                let w = NSWindow(contentViewController: NSHostingController(
                    rootView: MenuView(store: DisplayStore())))
                w.title = "MonitorPilot — popover"
                w.styleMask = [.titled, .closable]
                w.center()
                w.isReleasedWhenClosed = false
                w.makeKeyAndOrderFront(nil)
                previewWindow = w
            }
        } else {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        if ConfigStore.load().hotkeysEnabled {
            HotkeyService.registerDefaults()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: CLI.offNotification("pip"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PIPController.shared.closeAll() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: CLI.offNotification("stream"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { StreamService.shared.stopAll() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: CLI.brightnessNotification, object: nil, queue: .main) { n in
            guard let info = n.userInfo,
                  let id = (info["display"] as? NSNumber)?.uint32Value,
                  let value = (info["value"] as? NSNumber)?.floatValue else { return }
            let software = (info["software"] as? NSNumber)?.boolValue ?? false
            if software {
                var adj = ColorService.applied[id] ?? .neutral
                adj.brightness = min(max(value, 0), 1)
                _ = ColorService.apply(id, adj)
            } else {
                BrightnessService.setBrightness(id, value)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            PIPController.shared.closeAll()
            StreamService.shared.stopAll()
            AppDelegate.teardownHiDPI?()
        }
        VirtualDisplayService.shared.destroyAll()
        SystemService.preventSleep(false)
        ColorService.resetAll()
    }
}
