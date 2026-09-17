import Foundation
import CoreGraphics
import AppKit

enum CLI {
    struct Command {
        var operation: String
        var feature: String?
        var value: String?
        var display: String?
    }

    static func parse(_ args: [String]) -> Command? {
        var a = args
        guard !a.isEmpty else { return nil }
        let op = a.removeFirst()
        switch op {
        case "list", "restore-gamma":
            return Command(operation: op, feature: nil, value: nil, display: a.first)
        case "mirror", "unmirror", "connect", "disconnect", "hdr", "nightshift", "rotation":
            return Command(operation: op, feature: a.first, value: a.count > 1 ? a[1] : nil,
                           display: a.first)
        case "modes":
            return Command(operation: op, feature: nil, value: nil, display: a.first)
        case "pip":
            guard let source = a.first else { return nil }
            if source == "off" { return Command(operation: op, feature: "off", value: nil, display: nil) }
            var anchor: String?
            if let i = a.firstIndex(of: "--of"), i + 1 < a.count { anchor = a[i + 1] }
            return Command(operation: op, feature: source, value: nil, display: anchor)
        case "stream":
            guard let source = a.first else { return nil }
            if source == "off" { return Command(operation: op, feature: "off", value: nil, display: nil) }
            var target: String?
            if let i = a.firstIndex(of: "--to"), i + 1 < a.count { target = a[i + 1] }
            return Command(operation: op, feature: source, value: target, display: nil)
        case "preset":
            return Command(operation: op, feature: a.first, value: a.count > 1 ? a[1] : nil,
                           display: a.count > 2 ? a[2] : nil)
        case "get":
            guard let feature = a.first else { return nil }
            return Command(operation: op, feature: feature, value: nil,
                           display: a.count > 1 ? a[1] : nil)
        case "set":
            guard a.count >= 2 else { return nil }
            return Command(operation: op, feature: a[0], value: a[1],
                           display: a.count > 2 ? a[2] : nil)
        case "ddc":
            if a == ["ports"] { return Command(operation: "ddc-ports", feature: nil, value: nil, display: nil) }
            guard a.count >= 2 else { return nil }
            let sub = a.removeFirst()
            let feature = a.removeFirst()
            let value = sub == "set" ? a.first : nil
            let display = sub == "set"
                ? (a.count > 1 ? a[1] : nil)
                : a.first
            return Command(operation: "ddc-\(sub)", feature: feature, value: value, display: display)
        default:
            return nil
        }
    }

    static func run(_ args: [String]) -> Int32 {
        guard let cmd = parse(args) else {
            print(usage)
            return 64
        }
        switch cmd.operation {
        case "list":
            for d in DisplayManager.onlineDisplays() {
                let tags = [
                    d.isMain ? "main" : nil,
                    d.isBuiltin ? "builtin" : nil,
                ].compactMap { $0 }.joined(separator: ",")
                print("\(d.id)\t\(d.name)\t\(Int(d.sizePixels.width))×\(Int(d.sizePixels.height))\t\(tags)")
            }
            return 0

        case "modes":
            guard let d = DisplayManager.resolve(cmd.display) else { return fail("display não encontrado") }
            for m in ModeService.modes(for: d.id) {
                print("\(m.id)\t\(m.label)\(m.isCurrent ? "\t← atual" : "")")
            }
            return 0

        case "restore-gamma":
            ColorService.resetAll()
            print("gamma restaurada")
            return 0

        case "get":
            guard let d = DisplayManager.resolve(cmd.display) else { return fail("display não encontrado") }
            switch cmd.feature {
            case "brightness":
                print(String(format: "%.3f", BrightnessService.brightness(d.id)))
            case "software-brightness":
                print(String(format: "%.3f", BrightnessService.softwareBrightness(d.id)))
            default:
                return fail("feature desconhecida: \(cmd.feature ?? "")")
            }
            return 0

        case "set":
            guard let d = DisplayManager.resolve(cmd.display) else { return fail("display não encontrado") }
            switch cmd.feature {
            case "brightness":
                guard let v = parseLevel(cmd.value) else { return fail("valor inválido") }
                guard BrightnessService.hasHardwarePath(d.id) else {
                    return postBrightness(d.id, v, software: false)
                        ? 0 : fail("display sem brilho por hardware e app de menu bar fechado — abra o MonitorPilot.app")
                }
                return BrightnessService.setBrightness(d.id, v) ? 0 : fail("set falhou")
            case "software-brightness":
                guard let v = parseLevel(cmd.value) else { return fail("valor inválido") }
                return postBrightness(d.id, v, software: true)
                    ? 0 : fail("app de menu bar não está rodando (abra o MonitorPilot.app)")
            case "mode":
                guard let raw = cmd.value, let modeID = Int32(raw) else { return fail("modeID inválido") }
                return ModeService.setMode(d.id, modeID: modeID) ? 0 : fail("mudança de modo falhou")
            default:
                return fail("feature desconhecida: \(cmd.feature ?? "")")
            }

        case "ddc-ports":
            for line in DDCService.portReport() { print(line) }
            return 0

        case "ddc-get":
            guard let d = DisplayManager.resolve(cmd.display) else { return fail("display não encontrado") }
            guard let vcp = vcp(cmd.feature) else { return fail("vcp desconhecido") }
            guard let reading = DDCService.read(d.id, vcp: vcp) else { return fail("leitura DDC falhou") }
            print("\(reading.current)/\(reading.max)")
            return 0

        case "ddc-set":
            guard let d = DisplayManager.resolve(cmd.display) else { return fail("display não encontrado") }
            guard let vcp = vcp(cmd.feature), let raw = cmd.value, let v = UInt16(raw) else {
                return fail("uso: ddc set <feature> <valor>")
            }
            return DDCService.write(d.id, vcp: vcp, value: v) ? 0 : fail("escrita DDC falhou")

        case "mirror":
            guard let d = DisplayManager.resolve(cmd.feature),
                  let m = DisplayManager.resolve(cmd.value) else { return fail("uso: mirror <display> <master>") }
            return SystemService.setMirror(d.id, of: m.id) ? 0 : fail("mirror falhou")

        case "unmirror":
            guard let d = DisplayManager.resolve(cmd.feature) else { return fail("display não encontrado") }
            return SystemService.setMirror(d.id, of: nil) ? 0 : fail("unmirror falhou")

        case "connect", "disconnect":
            let on = cmd.operation == "connect"
            let id: CGDirectDisplayID
            if let d = DisplayManager.resolve(cmd.feature) { id = d.id }
            else if on, let raw = cmd.feature.flatMap(UInt32.init) { id = raw }
            else { return fail("display não encontrado") }
            guard SystemService.disconnectAvailable else { return fail("CGSConfigureDisplayEnabled indisponível neste macOS") }
            return SystemService.setConnected(id, on) ? 0 : fail("\(cmd.operation) falhou (nunca desconecto o último display)")

        case "hdr":
            PresetService.warmUpBlocking()
            switch cmd.feature {
            case "on", "off":
                guard let d = DisplayManager.resolve(cmd.value) else { return fail("display não encontrado") }
                let on = cmd.feature == "on"
                guard SystemService.setHDR(d.id, on) else { return fail("HDR set falhou") }
                var config = ConfigStore.load()
                var dc = config.displays[ConfigStore.stableKey(d)] ?? DisplayConfig()
                dc.hdr = on
                config.displays[ConfigStore.stableKey(d)] = dc
                ConfigStore.save(config)
                return 0
            default:
                guard let d = DisplayManager.resolve(cmd.feature) else { return fail("display não encontrado") }
                let managed = ConfigStore.load().displays[ConfigStore.stableKey(d)]?.hdr
                let managedStr = managed.map { $0 ? "on" : "off" } ?? "—"
                print("suportado: \(SystemService.hdrSupported(d.id)) · ativo: \(SystemService.hdrEnabled(d.id)) · gerenciado: \(managedStr)")
                return 0
            }

        case "nightshift":
            switch cmd.feature {
            case "on": return SystemService.setNightShift(enabled: true) ? 0 : fail("Night Shift falhou")
            case "off": return SystemService.setNightShift(enabled: false) ? 0 : fail("Night Shift falhou")
            default:
                guard let v = parseLevel(cmd.feature) else { return fail("uso: nightshift <on|off|0-1>") }
                _ = SystemService.setNightShift(enabled: v > 0)
                return SystemService.setNightShiftStrength(v) ? 0 : fail("Night Shift falhou")
            }

        case "preset":
            guard PresetService.available else { return fail("MonitorPanel.framework indisponível") }
            PresetService.warmUpBlocking()
            switch cmd.feature {
            case "list", nil:
                guard let d = DisplayManager.resolve(cmd.value) else { return fail("display não encontrado") }
                let list = PresetService.presets(for: d.id)
                guard !list.isEmpty else { return fail("display sem presets Apple") }
                let active = PresetService.activePresetIndex(d.id)
                for p in list {
                    let mark = p.index == active ? " ← ativo" : ""
                    print("[\(p.index)] \(p.name)\(p.detail.map { " · \($0)" } ?? "")\(mark)")
                }
                return 0
            case "set":
                guard let raw = cmd.value, let idx = Int(raw) else { return fail("uso: preset set <índice> [display]") }
                guard let d = DisplayManager.resolve(cmd.display) else { return fail("display não encontrado") }
                guard PresetService.setPreset(d.id, index: idx) else { return fail("preset set falhou (índice inválido?)") }
                Thread.sleep(forTimeInterval: 2)
                print("ativo agora: \(PresetService.activePresetIndex(d.id).map(String.init) ?? "?")")
                return 0
            default:
                return fail("uso: preset list [display] · preset set <índice> [display]")
            }

        case "rotation":
            guard let d = DisplayManager.resolve(cmd.display) else { return fail("display não encontrado") }
            print("\(Int(CGDisplayRotation(d.id)))°")
            return 0

        case "pip", "stream":
            return runCapture(cmd)

        default:
            print(usage)
            return 64
        }
    }

    static let brightnessNotification = Notification.Name("app.monitorpilot.brightness.set")
    static let bundleID = "app.monitorpilot"

    static func postBrightness(_ id: CGDirectDisplayID, _ value: Float, software: Bool) -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            brightnessNotification, object: nil,
            userInfo: ["display": Int(id), "value": Double(value), "software": software],
            deliverImmediately: true)
        print("aplicado pelo app residente (\(software ? "gamma" : "auto"))")
        return true
    }

    static func offNotification(_ kind: String) -> Notification.Name {
        Notification.Name("app.monitorpilot.\(kind).off")
    }

    private static func runCapture(_ cmd: Command) -> Int32 {
        let kind = cmd.operation
        if cmd.feature == "off" {
            DistributedNotificationCenter.default().postNotificationName(
                offNotification(kind), object: nil, userInfo: nil, deliverImmediately: true)
            print("pedido de parada enviado (\(kind))")
            return 0
        }
        guard let source = DisplayManager.resolve(cmd.feature) else {
            return fail("display de origem não encontrado")
        }
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        guard ScreenCapturePermission.granted else {
            ScreenCapturePermission.request()
            return fail("sem permissão de Gravação de Tela — autorize em Privacidade e Segurança")
        }

        var ok = false
        if kind == "pip" {
            guard let anchor = DisplayManager.resolve(cmd.display) else {
                return fail("display de destino (--of) não encontrado")
            }
            var config = PIPConfig()
            config.sourceDisplayKey = ConfigStore.stableKey(source)
            ok = MainActor.assumeIsolated {
                PIPController.shared.open(anchorKey: ConfigStore.stableKey(anchor),
                                          source: source.id, config: config, askPermission: false)
            }
        } else {
            guard cmd.value == "virtual" else { return fail("uso: stream <fonte> --to virtual") }
            let sem = DispatchSemaphore(value: 0)
            var result = false
            Task { @MainActor in
                result = await StreamService.shared.streamToVirtual(source: source, askPermission: false)
                sem.signal()
            }
            while sem.wait(timeout: .now() + 0.05) == .timedOut {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            ok = result
        }
        guard ok else { return fail("\(kind) falhou") }
        print("\(kind) ativo — Ctrl-C ou `monitorpilot \(kind) off` para encerrar")

        DistributedNotificationCenter.default().addObserver(
            forName: offNotification(kind), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if kind == "pip" { PIPController.shared.closeAll() }
                else { StreamService.shared.stopAll() }
            }
            exit(0)
        }
        NSApplication.shared.run()
        return 0
    }

    static func parseLevel(_ raw: String?) -> Float? {
        guard var raw else { return nil }
        var percent = false
        if raw.hasSuffix("%") { percent = true; raw.removeLast() }
        guard let v = Float(raw) else { return nil }
        if percent || v > 1 { return min(max(v / 100, 0), 1) }
        return min(max(v, 0), 1)
    }

    static func vcp(_ name: String?) -> DDCService.VCP? {
        switch name {
        case "brightness": .brightness
        case "contrast": .contrast
        case "volume": .volume
        case "mute": .mute
        case "input": .inputSource
        case "power": .power
        default: nil
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("erro: \(message)\n".utf8))
        return 1
    }

    static let usage = """
    MonitorPilot — controle de displays (uso pessoal)

      monitorpilot list
      monitorpilot modes [display]
      monitorpilot get brightness [display]
      monitorpilot set brightness <0-1|%> [display]
      monitorpilot set software-brightness <0-1|%> [display]
      monitorpilot set mode <modeID> [display]
      monitorpilot ddc get <brightness|contrast|volume|input> [display]
      monitorpilot ddc set <feature> <valor> [display]
      monitorpilot mirror <display> <master> · unmirror <display>
      monitorpilot connect <display> · disconnect <display>
      monitorpilot hdr [on|off] <display>
      monitorpilot nightshift <on|off|0-1>
      monitorpilot preset list [display] · preset set <índice> [display]
      monitorpilot rotation [display]
      monitorpilot pip <fonte> [--of <display>] · monitorpilot pip off
      monitorpilot stream <fonte> --to virtual · monitorpilot stream off
      monitorpilot restore-gamma

    [display] = displayID ou parte do nome; vazio = display principal.
    Sem argumentos = abre o app de menu bar.
    """
}
