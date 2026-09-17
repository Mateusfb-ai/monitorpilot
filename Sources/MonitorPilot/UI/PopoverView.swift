import SwiftUI
import CoreGraphics
import AppKit

// Popover estilo BetterDisplay: card por display (header + sliders),
// lista de submenus com ícone + chevron, footer com ações.

struct MenuView: View {
    @ObservedObject var store: DisplayStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cards

            Divider()

            HStack(spacing: 10) {
                GlassIconButton(systemImage: "questionmark.circle", help: "Identificar monitores") {
                    SystemService.identifyDisplays()
                }
                Spacer()
                GlassIconButton(systemImage: "gearshape", help: "Ajustes") {
                    SettingsWindowManager.shared.open(store: store)
                }
                GlassIconButton(systemImage: "power", help: "Sair") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { store.refresh() }
    }

    @ViewBuilder private var cards: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 8) {
                    ForEach(store.displays) { display in
                        DisplayCard(display: display, store: store)
                    }
                }
            }
        } else {
            ForEach(store.displays) { display in
                DisplayCard(display: display, store: store)
            }
        }
    }
}

// MARK: Card do display (header cinza + sliders, como no BetterDisplay)

private struct DisplayCard: View {
    let display: DisplayInfo
    @ObservedObject var store: DisplayStore
    @State private var showSubmenus = ProcessInfo.processInfo.environment["MONITORPILOT_PREVIEW_EXPANDED"] == "1"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                Text(display.name).font(.system(.body, weight: .semibold))
                if display.isMain {
                    Image(systemName: "m.circle.fill")
                        .foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Text("\(Int(display.sizePixels.width))×\(Int(display.sizePixels.height))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider().padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 10) {
                // Brilho combinado
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(brightnessLabel).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((store.brightness[display.id] ?? 1) * 100))%")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: Int((store.brightness[display.id] ?? 1) * 100))
                    }
                    LabeledSlider(
                        icon: (store.brightness[display.id] ?? 1) > 1 ? "sun.max.trianglebadge.exclamationmark.fill" : "sun.max.fill",
                        value: Binding(
                            get: { store.brightness[display.id] ?? 1 },
                            set: { store.setBrightness(display.id, $0) }
                        ), range: 0...Double(store.combinedMax(display)), showValue: false
                    )
                }

                // Resolução (slider sobre a escada de resoluções)
                ResolutionSliderRow(display: display, store: store)

                DisclosureGroup(isExpanded: $showSubmenus.animation(.snappy(duration: 0.28))) {
                    SubmenuList(display: display, store: store)
                        .padding(.top, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } label: {
                    Text("Opções do monitor").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
        }
        .monitorpilotGlassCard()
        .animation(.snappy(duration: 0.28), value: showSubmenus)
    }

    private var brightnessLabel: String {
        guard store.upscalingOn[display.id] == true else { return "Brilho (Combinado)" }
        return UpscalingService.mode(display.id) == .edr
            ? "Brilho (Combinado, Upscaling)" : "Brilho (Combinado, Realce SDR)"
    }
}

// MARK: Slider de resolução

private struct ResolutionSliderRow: View {
    let display: DisplayInfo
    @ObservedObject var store: DisplayStore
    @State private var ladder: [DisplayMode] = []
    @State private var index: Double = 0
    @State private var pending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Resolução").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(label).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption).foregroundStyle(.secondary).frame(width: 16)
                Slider(
                    value: $index,
                    in: 0...Double(max(ladder.count - 1, 1)),
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { apply() }
                    }
                )
                .controlSize(.small)
                .disabled(ladder.count < 2)
            }
        }
        .onAppear { reload() }
    }

    private var label: String {
        guard !ladder.isEmpty else { return "—" }
        let m = ladder[min(Int(index), ladder.count - 1)]
        if let pct = ModeService.scalePercent(display.id, logicalWidth: m.width) {
            return "\(m.width)x\(m.height) · \(pct)%"
        }
        return "\(m.width)x\(m.height)"
    }

    private func reload() {
        let showAll = store.showAllModes(display)
        ladder = ModeService.resolutionLadder(for: display.id, showAll: showAll)
        let current = ModeService.modes(for: display.id, showAll: showAll).first(where: \.isCurrent)
        if let i = ladder.firstIndex(where: { $0.width == current?.width && $0.height == current?.height }) {
            index = Double(i)
        }
    }

    private func apply() {
        guard !ladder.isEmpty else { return }
        let target = ladder[min(Int(index), ladder.count - 1)]
        guard !target.isCurrent else { return }
        ModeService.setMode(display.id, modeID: target.id)
        store.userChangedLayout(display)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { reload() }
    }
}

// MARK: Lista de submenus (linhas com ícone + chevron/menu)

private struct SubmenuList: View {
    let display: DisplayInfo
    @ObservedObject var store: DisplayStore
    @ObservedObject private var pip = PIPController.shared
    @ObservedObject private var streams = StreamService.shared
    @State private var showImageAdjustments = false
    @State private var showPIPAdjustments = false
    @State private var cropDraft: [Double]?

    private var anchorKey: String { ConfigStore.stableKey(display) }

    private func openPIP(source: DisplayInfo, crop: CGRect?) {
        var config = store.displayConfig(display).pip ?? PIPConfig()
        config.sourceDisplayKey = ConfigStore.stableKey(source)
        config.crop = crop
        _ = pip.open(anchorKey: anchorKey, source: source.id, config: config, askPermission: true)
    }

    private func pipBinding<V>(_ key: WritableKeyPath<PIPConfig, V>) -> Binding<V> {
        Binding(
            get: { pip.session(for: anchorKey)?.config[keyPath: key]
                    ?? PIPConfig()[keyPath: key] },
            set: { v in pip.update(anchorKey: anchorKey) { $0[keyPath: key] = v } }
        )
    }

    /// Recorte normalizado [x, y, largura, altura]. O slider mexe num rascunho
    /// local e só COMMITA ao soltar — commitar por tick recriaria a config da
    /// stream dezenas de vezes por arrasto.
    private func currentCrop() -> [Double] {
        let c = pip.session(for: anchorKey)?.config.crop
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return [c.origin.x, c.origin.y, c.width, c.height]
    }

    private func cropSlider(_ label: String, _ index: Int,
                            _ range: ClosedRange<Double>) -> some View {
        let base = currentCrop()
        let value = Binding<Double>(
            get: { (cropDraft ?? base)[index] },
            set: { v in
                var draft = cropDraft ?? base
                draft[index] = v
                cropDraft = draft
            }
        )
        return HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Slider(value: value, in: range) { editing in
                guard !editing, let draft = cropDraft else { return }
                cropDraft = nil
                pip.update(anchorKey: anchorKey) {
                    $0.crop = CGRect(x: draft[0], y: draft[1], width: draft[2], height: draft[3])
                }
            }
            .controlSize(.mini)
        }
    }

    private func pipSlider(_ label: String, _ value: Binding<Double>,
                           _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Slider(value: value, in: range).controlSize(.mini)
        }
    }

    private func presetLabel(_ p: XDRPreset) -> String {
        p.detail.map { "\(p.name) · \($0)" } ?? p.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Modo de exibição
            RowMenu(icon: "rectangle.on.rectangle", title: "Modo de exibição") {
                Toggle("Mostrar todos (HiDPI)", isOn: Binding(
                    get: { store.showAllModes(display) },
                    set: { store.setShowAllModes(display, $0) }
                ))
                Divider()
                ForEach(ModeService.modes(for: display.id,
                                          showAll: store.showAllModes(display)).prefix(60)) { m in
                    Button {
                        ModeService.setMode(display.id, modeID: m.id)
                        store.userChangedLayout(display)
                    } label: {
                        let label = m.isUserVisible ? m.label : "\(m.label) ·"
                        if m.isCurrent { Label(label, systemImage: "checkmark") }
                        else { Text(label) }
                    }
                }
            }

            // Taxa de atualização
            RowMenu(icon: "gauge.with.dots.needle.67percent", title: "Taxa de atualização") {
                let current = ModeService.modes(for: display.id, showAll: store.showAllModes(display))
                    .first(where: \.isCurrent)
                ForEach(ModeService.refreshOptions(for: display.id,
                                                   width: current?.width ?? 0,
                                                   height: current?.height ?? 0,
                                                   showAll: store.showAllModes(display))) { m in
                    Button {
                        ModeService.setMode(display.id, modeID: m.id)
                        store.userChangedLayout(display)
                    } label: {
                        let hz = String(format: "%.4g Hz", m.refreshRate)
                        if m.isCurrent { Label(hz, systemImage: "checkmark") } else { Text(hz) }
                    }
                }
            }

            // Modo de cor (perfis ICC — ColorSync público)
            RowMenu(icon: "paintpalette", title: "Modo de cor",
                    detail: store.colorProfileName[display.id]) {
                Button("Padrão de fábrica") {
                    ColorProfileService.resetToFactory(display.id)
                    store.refresh()
                }
                Divider()
                let currentName = store.colorProfileName[display.id]
                ForEach(ColorProfileService.installedProfiles().prefix(40)) { p in
                    Button {
                        ColorProfileService.setProfile(display.id, url: p.url)
                        store.refresh()
                    } label: {
                        if currentName == p.name { Label(p.name, systemImage: "checkmark") }
                        else { Text(p.name) }
                    }
                }
            }

            // Espelhamento
            RowMenu(icon: "rectangle.on.rectangle.angled", title: "Espelhamento do Monitor") {
                ForEach(store.displays.filter { $0.id != display.id }) { other in
                    Button("Espelhar de \(other.name)") {
                        SystemService.setMirror(display.id, of: other.id)
                        store.userChangedLayout(display)
                    }
                }
                if SystemService.mirrorMaster(display.id) != nil {
                    Button("Desativar espelhamento") {
                        SystemService.setMirror(display.id, of: nil)
                        store.userChangedLayout(display)
                    }
                }
            }

            // Monitor de Transmissão (ScreenCaptureKit + tela virtual)
            RowMenu(icon: "rectangle.inset.filled.on.rectangle", title: "Monitor de Transmissão",
                    detail: streams.session(source: display.id) != nil ? "ao vivo" : nil) {
                Button("Transmitir esta tela para uma tela virtual") {
                    Task { @MainActor in
                        _ = await streams.streamToVirtual(source: display, askPermission: true)
                    }
                }
                let virtuals = VirtualDisplayService.shared.screens
                if !virtuals.isEmpty {
                    Divider()
                    ForEach(virtuals) { v in
                        Button("Transmitir \(v.name) para esta tela") {
                            _ = streams.streamVirtual(v, to: display, askPermission: true)
                        }
                    }
                }
                if !streams.sessions.isEmpty {
                    Divider()
                    ForEach(streams.sessions) { s in
                        Button("Parar: \(s.label)", role: .destructive) { streams.stop(s) }
                    }
                }
                if !ScreenCapturePermission.granted {
                    Divider()
                    Button("Abrir Privacidade…") { ScreenCapturePermission.openPrivacySettings() }
                }
            }

            // PIP — janela flutuante com a captura ao vivo de outra tela
            RowMenu(icon: "pip", title: "PIP",
                    detail: pip.isActive(anchorKey) ? "ativo" : nil) {
                ForEach(store.displays.filter { $0.id != display.id }) { other in
                    Button("Mostrar \(other.name)") { openPIP(source: other, crop: nil) }
                }
                Button("Região desta tela…") {
                    openPIP(source: display,
                            crop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
                }
                if pip.isActive(anchorKey) {
                    Divider()
                    Toggle("Sempre no topo", isOn: pipBinding(\.alwaysOnTop))
                    Toggle("Atravessar cliques", isOn: pipBinding(\.clickThrough))
                    Toggle("Mostrar cursor", isOn: pipBinding(\.showCursor))
                    Toggle("Abrir no lançamento", isOn: pipBinding(\.autoStart))
                    Divider()
                    Button("Fechar PIP", role: .destructive) {
                        pip.close(anchorKey: anchorKey)
                    }
                }
                if !ScreenCapturePermission.granted {
                    Divider()
                    Button("Abrir Privacidade…") { ScreenCapturePermission.openPrivacySettings() }
                }
            }

            if pip.isActive(anchorKey) {
                RowDisclosure(icon: "slider.horizontal.3", title: "Ajustes do PIP",
                              isExpanded: $showPIPAdjustments) {
                    VStack(spacing: 6) {
                        pipSlider("Opacidade", pipBinding(\.alpha), 0.2...1)
                        HStack(spacing: 6) {
                            Text("Ampliação").font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 82, alignment: .leading)
                            Button("−") { pip.setMagnification(anchorKey: anchorKey, factor: 0.8) }
                            Button("+") { pip.setMagnification(anchorKey: anchorKey, factor: 1.25) }
                            Spacer()
                        }
                        .font(.caption2)
                        cropSlider("Recorte X", 0, 0...0.9)
                        cropSlider("Recorte Y", 1, 0...0.9)
                        cropSlider("Recorte L", 2, 0.1...1)
                        cropSlider("Recorte A", 3, 0.1...1)
                        Button("Sem recorte") {
                            pip.update(anchorKey: anchorKey) { $0.crop = nil }
                        }
                        .font(.caption)
                    }
                    .padding(.leading, 24)
                }
            }

            // Mover monitor no layout (API pública CGConfigureDisplayOrigin)
            if store.displays.count > 1 {
                RowMenu(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "Mover Monitor") {
                    ForEach(store.displays.filter { $0.id != display.id }) { other in
                        Menu(other.name) {
                            ForEach(LayoutPlanner.Side.allCases, id: \.self) { side in
                                Button("Colocar \(side.label) \(other.name)") {
                                    LayoutService.move(display.id, relativeTo: other.id, side: side)
                                    store.userChangedLayout(display)
                                }
                            }
                        }
                    }
                }
            }

            // Rotação (escrita via MPDisplay.setOrientation:, com confirmação
            // de 10s que reverte sozinha — igual ao macOS).
            RowMenu(icon: "rotate.right", title: "Rotação da Tela",
                    detail: "\(RotationService.current(display.id))°") {
                if !RotationService.ready {
                    Text("Carregando…").foregroundStyle(.secondary)
                } else if RotationService.canRotate(display.id) {
                    ForEach(RotationPolicy.angles, id: \.self) { angle in
                        Button {
                            store.setRotation(display, degrees: angle)
                        } label: {
                            if RotationService.current(display.id) == angle {
                                Label("\(angle)°", systemImage: "checkmark")
                            } else {
                                Text("\(angle)°")
                            }
                        }
                    }
                } else {
                    Text("Este monitor não permite rotação").foregroundStyle(.secondary)
                }
            }

            if let pending = store.rotationPending[display.id] {
                HStack(spacing: 8) {
                    RowIcon(icon: "clock.arrow.circlepath")
                    Text("Manter rotação? \(pending.seconds)s")
                        .font(.caption)
                    Spacer()
                    Button("Reverter") { store.revertRotation(display) }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                    Button("Manter") { store.keepRotation(display) }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain)
                }
                .padding(.vertical, 3).padding(.horizontal, 4)
            }

            // Ajustes de imagem (inline)
            RowDisclosure(icon: "photo.on.rectangle.angled", title: "Ajustes de Imagem",
                          isExpanded: $showImageAdjustments) {
                VStack(spacing: 6) {
                    miniSlider("Dimming", \.brightness, 0...1)
                    miniSlider("Contraste", \.contrast, -1...1)
                    miniSlider("Temperatura", \.temperature, -1...1)
                    miniSlider("Gamma", \.gamma, 0.5...2)
                    Button("Neutro") {
                        store.setColor(display.id) { $0 = .neutral }
                        ColorService.reset(display.id)
                    }
                    .font(.caption)
                }
                .padding(.leading, 24)
            }

            // Predefinições Apple (XDR reference modes) via MonitorPanel
            if let presets = store.presets[display.id], !presets.isEmpty {
                RowMenu(icon: "slider.horizontal.2.square", title: "Predefinição de XDR") {
                    ForEach(presets) { p in
                        Button {
                            store.setPreset(display, index: p.index)
                        } label: {
                            if store.activePreset[display.id] == p.index {
                                Label(presetLabel(p), systemImage: "checkmark")
                            } else {
                                Text(presetLabel(p))
                            }
                        }
                    }
                    Divider()
                    Text("Preset de referência limita brilho e desativa upscaling EDR")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Proteção de configuração
            RowToggle(icon: "lock.shield", title: "Proteger configuração", isOn: Binding(
                get: { store.layoutProtected(display) },
                set: { store.setLayoutProtection(display, $0) }
            ))

            // Gerenciar monitor
            RowMenu(icon: "gearshape.2", title: "Gerenciar Monitor") {
                Button("Identificar visualmente") { SystemService.identifyDisplays() }
                if !display.isBuiltin, SystemService.disconnectAvailable {
                    Button("Desconectar (soft)", role: .destructive) {
                        store.markSoftDisconnected(display)
                        SystemService.setConnected(display.id, false)
                        store.refresh()
                    }
                }
                if SystemService.hdrSupported(display.id) {
                    Button(SystemService.hdrEnabled(display.id) ? "Desligar HDR" : "Ligar HDR") {
                        let on = !SystemService.hdrEnabled(display.id)
                        _ = SystemService.setHDR(display.id, on)
                        store.updateDisplayConfig(display) { $0.hdr = on }
                    }
                    Text("Mesmo controle de Ajustes › Monitores › High Dynamic Range.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let hidpi = store.hiDPIToggle[display.id] {
                // Display com HiDPI nativo: alterna com o modo gêmeo sem HiDPI.
                RowToggle(icon: "square.resize.up", title: "Alta Resolução (HiDPI)", isOn: Binding(
                    get: { hidpi.isHiDPI },
                    set: {
                        HiDPIToggleService.set(display.id, hiDPI: $0)
                        store.userChangedLayout(display)
                    }
                ))
            } else if HiDPIService.isAvailable {
                // Sem HiDPI nativo: caminho tela virtual espelhada.
                RowToggle(icon: "square.resize.up", title: "Alta Resolução (tela virtual)",
                          isOn: Binding(
                    get: { store.hiDPIVirtualOn(display) && !store.hiDPISharpOn(display) },
                    set: { store.setHiDPIVirtual(display, $0, sharp: false) }
                ))
            }

            if HiDPIService.isAvailable {
                // "Nítido 2×": virtual com o dobro dos pixels do painel, espelhada em
                // downscale — a resolução lógica fica a nativa, renderizada em 2×.
                // É o que faz um 1080p parecer Retina (Dell 1080×1920 → 1080×1920 nítido).
                let (lw, lh) = HiDPIService.sharpLogicalSize(display.id)
                RowToggle(icon: "sparkles.rectangle.stack", title: "Nítido 2× (\(lw)×\(lh))",
                          isOn: Binding(
                    get: { store.hiDPISharpOn(display) },
                    set: { store.setHiDPIVirtual(display, $0, sharp: true) }
                ))
            }

            if store.notchSupported[display.id] == true {
                RowToggle(icon: "rectangle.topthird.inset.filled", title: "Exibir Notch", isOn: Binding(
                    get: { NotchService.showsNotch(display.id) },
                    set: { NotchService.set(display.id, showNotch: $0); store.userChangedLayout(display) }
                ))
            }

            // Linhas de ação direta
            if !display.isMain {
                RowButton(icon: "m.circle", title: "Definir como Monitor Principal") {
                    SystemService.setMain(display.id)
                    store.refresh()
                }
            }

            RowToggle(
                icon: "sparkles",
                title: UpscalingService.mode(display.id) == .edr
                    ? "Ampliação de brilho" : "Ampliação de brilho (realce SDR)",
                isOn: Binding(
                    get: { store.upscalingOn[display.id] ?? false },
                    set: { store.setUpscaling(display, $0) }
                )
            )

            if store.ambientSupported[display.id] == true {
                RowToggle(icon: "sun.max.circle", title: "Brilho Automático", isOn: Binding(
                    get: { AmbientService.enabled(display.id) ?? false },
                    set: { AmbientService.set(display.id, $0); store.objectWillChange.send() }
                ))
            } else if !AmbientService.isAvailable {
                HStack(spacing: 8) {
                    RowIcon(icon: "sun.max.circle")
                    Text("Brilho Automático").font(.callout)
                    Spacer()
                    Text("Indisponível neste macOS").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3).padding(.horizontal, 4)
            }

            RowToggle(icon: "moon.stars", title: "Night Shift", isOn: Binding(
                get: { store.nightShift },
                set: { store.nightShift = $0; SystemService.setNightShift(enabled: $0) }
            ))

            RowToggle(icon: "cup.and.saucer", title: "Impedir de dormir", isOn: Binding(
                get: { store.preventSleep },
                set: { store.preventSleep = $0; SystemService.preventSleep($0) }
            ))
        }
    }

    private func miniSlider(_ label: String, _ key: WritableKeyPath<ColorAdjustments, Float>,
                            _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Slider(value: Binding(
                get: { Double(store.color[display.id]?[keyPath: key] ?? ColorAdjustments.neutral[keyPath: key]) },
                set: { v in store.setColor(display.id) { $0[keyPath: key] = Float(v) } }
            ), in: range)
            .controlSize(.mini)
        }
    }
}

// MARK: Componentes de linha (estilo BetterDisplay: ícone + título + chevron)

private struct RowMenu<Content: View>: View {
    let icon: String
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 8) {
                RowIcon(icon: icon)
                Text(title).font(.callout)
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding(.vertical, 3).padding(.horizontal, 4)
    }
}

private struct RowButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RowIcon(icon: icon)
                Text(title).font(.callout)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3).padding(.horizontal, 4)
    }
}

private struct RowToggle: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            RowIcon(icon: icon)
                .symbolEffect(.bounce, value: isOn)
                .symbolEffectsRemoved(reduceMotion)
            Text(title).font(.callout)
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
    }
}

private struct RowDisclosure<Content: View>: View {
    let icon: String
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    RowIcon(icon: icon)
                    Text(title).font(.callout)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded { content }
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
    }
}

private struct RowIcon: View {
    let icon: String
    var body: some View {
        Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.tint.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: Slider com ícone (compartilhado com a janela de Ajustes)

struct LabeledSlider: View {
    let icon: String
    @Binding var value: Float
    var range: ClosedRange<Double> = 0...1
    var showValue: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Slider(value: Binding(get: { Double(value) }, set: { value = Float($0) }), in: range)
                .controlSize(.small)
            if showValue {
                Text(range.lowerBound == 0 ? "\(Int(value * 100))%" : String(format: "%.2f", value))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(value * 100))
            }
        }
    }
}
