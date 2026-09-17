import SwiftUI
import AppKit
import CoreGraphics

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    func open(store: DisplayStore) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let view = SettingsRootView(store: store, virtuals: VirtualDisplayService.shared)
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "MonitorPilot"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 720, height: 480))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct SettingsRootView: View {
    @ObservedObject var store: DisplayStore
    @ObservedObject var virtuals: VirtualDisplayService
    @State private var selection: Pane? = .displays

    enum Pane: Hashable { case displays, color, virtuals, system }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Displays", systemImage: "display").tag(Pane.displays)
                Label("Cor e imagem", systemImage: "paintpalette").tag(Pane.color)
                Label("Telas virtuais", systemImage: "rectangle.dashed.badge.record").tag(Pane.virtuals)
                Label("Sistema", systemImage: "gearshape.2").tag(Pane.system)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection ?? .displays {
            case .displays: DisplaysPaneView(store: store)
            case .color: ColorPaneView(store: store)
            case .virtuals: VirtualsPaneView(virtuals: virtuals, store: store)
            case .system: SystemPaneView(store: store)
            }
        }
        .frame(minWidth: 680, minHeight: 440)
    }
}

struct DisplaysPaneView: View {
    @ObservedObject var store: DisplayStore

    var body: some View {
        Form {
            ForEach(store.displays) { d in
                Section(d.name) {
                    LabeledSlider(icon: "sun.max.fill", value: Binding(
                        get: { store.brightness[d.id] ?? 1 },
                        set: { store.setBrightness(d.id, $0) }
                    ))
                    ModeRow(display: d)
                    HStack {
                        Text("Rotação atual").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(CGDisplayRotation(d.id)))°")
                    }.font(.callout)
                    if SystemService.hdrSupported(d.id) {
                        Toggle("HDR", isOn: Binding(
                            get: { SystemService.hdrEnabled(d.id) },
                            set: { on in
                                _ = SystemService.setHDR(d.id, on)
                                store.updateDisplayConfig(d) { $0.hdr = on }
                            }
                        ))
                        Text("Mesmo controle de Ajustes › Monitores › High Dynamic Range.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !d.isBuiltin, SystemService.disconnectAvailable {
                        Button("Desconectar (soft)", role: .destructive) {
                            store.markSoftDisconnected(d)
                            SystemService.setConnected(d.id, false)
                            store.refresh()
                        }
                        .help("Remove do layout sem tocar no cabo. Reconecte pelo cabo ou reinicie o app em caso de problema.")
                    }
                }
                Section("\(d.name) — brilho combinado e upscaling") {
                    if UpscalingService.supportsUpscaling(d.id) {
                        Toggle("Ampliação de brilho (XDR/HDR)", isOn: Binding(
                            get: { store.upscalingOn[d.id] ?? false },
                            set: { store.setUpscaling(d, $0) }
                        ))
                        LabeledContent("Headroom EDR") {
                            Text(String(format: "potencial %.1f× · atual %.1f×",
                                        UpscalingService.potentialHeadroom(d.id),
                                        UpscalingService.currentHeadroom(d.id)))
                        }
                        LabeledContent("Valor máximo de upscaling combinado") {
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(store.displayConfig(d).maxBoostPercent) },
                                    set: { v in store.updateDisplayConfig(d) { $0.maxBoostPercent = Float(v) } }
                                ), in: 100...300, step: 5).frame(width: 180)
                                Text("\(Int(store.displayConfig(d).maxBoostPercent))%")
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        Text("Sem headroom EDR neste display (upscaling indisponível).")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                    LabeledContent("Ponto de comutação software/hardware") {
                        HStack {
                            Slider(value: Binding(
                                get: { Double(store.displayConfig(d).combinedSwitchpoint) },
                                set: { v in store.updateDisplayConfig(d) { $0.combinedSwitchpoint = Float(v) } }
                            ), in: 0.1...0.9).frame(width: 180)
                            Text("\(Int(store.displayConfig(d).combinedSwitchpoint * 100))%")
                                .monospacedDigit()
                        }
                    }
                }
            }
            if !store.softDisconnectedKeys.isEmpty {
                Section("Desconectados por você") {
                    ForEach(store.softDisconnectedKeys, id: \.self) { key in
                        HStack {
                            Text(key).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Reconectar") { store.reconnect(key: key) }
                        }
                    }
                    Text("Monitor tirado do layout com \"Desconectar (soft)\". Some do menu do sistema até reconectar aqui.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("DDC — ajuste fino (global)") {
                ddcStepper("Tentativas em caso de falha", \.writeAttempts, 1...8)
                ddcStepper("Envios por comando", \.sendsPerCommand, 1...4)
                ddcStepperMs("Atraso entre comandos (ms)", \.delayBetweenMs, 5...200)
                ddcStepperMs("Espera pela resposta na leitura (ms)", \.readReplyWaitMs, 10...200)
                Toggle("Ignorar erro de verificação na leitura", isOn: Binding(
                    get: { store.config.ddcTuning.ignoreReadChecksum },
                    set: { store.config.ddcTuning.ignoreReadChecksum = $0; applyTuning() }
                ))
            }
        }
        .formStyle(.grouped)
        .onAppear { store.refresh() }
    }

    private func ddcStepper(_ label: String, _ key: WritableKeyPath<DDCService.Tuning, Int>, _ range: ClosedRange<Int>) -> some View {
        Stepper("\(label): \(store.config.ddcTuning[keyPath: key])", value: Binding(
            get: { store.config.ddcTuning[keyPath: key] },
            set: { store.config.ddcTuning[keyPath: key] = $0; applyTuning() }
        ), in: range)
    }

    private func ddcStepperMs(_ label: String, _ key: WritableKeyPath<DDCService.Tuning, UInt32>, _ range: ClosedRange<UInt32>) -> some View {
        Stepper("\(label): \(store.config.ddcTuning[keyPath: key])", value: Binding(
            get: { store.config.ddcTuning[keyPath: key] },
            set: { store.config.ddcTuning[keyPath: key] = $0; applyTuning() }
        ), in: range, step: 5)
    }

    private func applyTuning() {
        DDCService.tuning = store.config.ddcTuning
        ConfigStore.save(store.config)
    }
}

private struct ModeRow: View {
    let display: DisplayInfo
    @State private var modes: [DisplayMode] = []
    @State private var selected: Int32 = 0

    var body: some View {
        Picker("Resolução e frequência", selection: $selected) {
            ForEach(modes) { m in Text(m.label).tag(m.id) }
        }
        .onAppear {
            modes = ModeService.modes(for: display.id)
            selected = modes.first(where: \.isCurrent)?.id ?? 0
        }
        .onChange(of: selected) { _, new in
            guard new != 0, new != modes.first(where: \.isCurrent)?.id else { return }
            ModeService.setMode(display.id, modeID: new)
            modes = ModeService.modes(for: display.id)
        }
    }
}

struct ColorPaneView: View {
    @ObservedObject var store: DisplayStore

    var body: some View {
        Form {
            ForEach(store.displays) { d in
                Section(d.name) {
                    slider(d, "Dimming", "circle.lefthalf.filled", \.brightness, 0...1)
                    slider(d, "Contraste", "circle.righthalf.filled", \.contrast, -1...1)
                    slider(d, "Temperatura", "thermometer.sun", \.temperature, -1...1)
                    slider(d, "Gamma", "waveform.path", \.gamma, 0.5...2)
                    slider(d, "Ganho R", "r.circle", \.gainR, 0...1)
                    slider(d, "Ganho G", "g.circle", \.gainG, 0...1)
                    slider(d, "Ganho B", "b.circle", \.gainB, 0...1)
                    Button("Neutro") {
                        store.setColor(d.id) { $0 = .neutral }
                        ColorService.reset(d.id)
                    }
                }
            }
            Text("Ajustes por gamma table — valem enquanto o app está aberto e são reaplicados no launch.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func slider(_ d: DisplayInfo, _ label: String, _ icon: String,
                        _ key: WritableKeyPath<ColorAdjustments, Float>,
                        _ range: ClosedRange<Double>) -> some View {
        LabeledContent(label) {
            LabeledSlider(icon: icon, value: Binding(
                get: { store.color[d.id]?[keyPath: key] ?? ColorAdjustments.neutral[keyPath: key] },
                set: { v in store.setColor(d.id) { $0[keyPath: key] = v } }
            ), range: range)
            .frame(width: 260)
        }
    }
}

struct VirtualsPaneView: View {
    @ObservedObject var virtuals: VirtualDisplayService
    @ObservedObject var store: DisplayStore
    @State private var name = "Tela Virtual"
    @State private var aspectW = 16
    @State private var aspectH = 9
    @State private var hiDPI = true

    var body: some View {
        Form {
            Section("Nova tela virtual") {
                TextField("Nome", text: $name)
                HStack {
                    Stepper("Aspecto: \(aspectW)", value: $aspectW, in: 1...64)
                    Stepper(": \(aspectH)", value: $aspectH, in: 1...64)
                }
                Toggle("HiDPI (Retina)", isOn: $hiDPI)
                Button("Criar") {
                    virtuals.create(name: name, aspectWidth: aspectW, aspectHeight: aspectH, hiDPI: hiDPI)
                    store.refresh()
                }
                .disabled(!VirtualDisplayService.isAvailable)
            }
            Section("Ativas") {
                if virtuals.screens.isEmpty {
                    Text("Nenhuma tela virtual.").foregroundStyle(.secondary)
                }
                ForEach(virtuals.screens) { s in
                    HStack {
                        Text("\(s.name) (\(s.aspectWidth):\(s.aspectHeight))")
                        Spacer()
                        if let id = s.displayID { Text("id \(id)").foregroundStyle(.secondary) }
                        Button("Remover", role: .destructive) {
                            virtuals.destroy(s)
                            store.refresh()
                        }
                    }
                }
            }
            Text("Use com mirror pra HiDPI flexível: crie a virtual e espelhe no display real (aba Displays / CLI `mirror`).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct SystemPaneView: View {
    @ObservedObject var store: DisplayStore
    @State private var nightShiftStrength: Float = 0.5

    var body: some View {
        Form {
            Section("Night Shift") {
                Toggle("Ativo", isOn: Binding(
                    get: { store.nightShift },
                    set: { store.nightShift = $0; SystemService.setNightShift(enabled: $0) }
                )).disabled(!SystemService.nightShiftAvailable)
                LabeledContent("Intensidade") {
                    LabeledSlider(icon: "moon.fill", value: Binding(
                        get: { nightShiftStrength },
                        set: { nightShiftStrength = $0; SystemService.setNightShiftStrength($0) }
                    )).frame(width: 260)
                }
            }
            Section("Energia") {
                Toggle("Impedir display de dormir", isOn: Binding(
                    get: { store.preventSleep },
                    set: { store.preventSleep = $0; SystemService.preventSleep($0) }
                ))
            }
            Section("Atalhos globais") {
                Text("⌥⌘↑ / ⌥⌘↓ — brilho do display principal\n⌥⌘← / ⌥⌘→ — brilho do display com o mouse")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Config") {
                LabeledContent("Arquivo", value: ConfigStore.url.path)
                Toggle("Restaurar ajustes no launch", isOn: Binding(
                    get: { store.config.restoreOnLaunch },
                    set: { store.config.restoreOnLaunch = $0; store.persist() }
                ))
            }
        }
        .formStyle(.grouped)
    }
}
