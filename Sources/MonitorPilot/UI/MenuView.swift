import SwiftUI
import CoreGraphics

@MainActor
final class DisplayStore: ObservableObject {
    private var screenObserver: NSObjectProtocol?
    private var screenTask: Task<Void, Never>?
    func startObservingScreens() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            screenTask?.cancel()
            screenTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                self?.refresh()
                self?.enforceProtection()
                self?.reconnectOrphansIfNeeded()
                self?.restoreHiDPIVirtualIfNeeded()
            }
        }
    }
    @Published var displays: [DisplayInfo] = []
    @Published var brightness: [CGDirectDisplayID: Float] = [:]
    @Published var color: [CGDirectDisplayID: ColorAdjustments] = [:]
    @Published var upscalingOn: [CGDirectDisplayID: Bool] = [:]
    @Published var preventSleep = false
    @Published var nightShift = false
    @Published var presets: [CGDirectDisplayID: [XDRPreset]] = [:]
    @Published var activePreset: [CGDirectDisplayID: Int] = [:]
    @Published var hiDPIToggle: [CGDirectDisplayID: (isHiDPI: Bool, twinID: Int32)] = [:]
    private var hiDPIEnabling: Set<CGDirectDisplayID> = []
    @Published var notchSupported: [CGDirectDisplayID: Bool] = [:]
    @Published var ambientSupported: [CGDirectDisplayID: Bool] = [:]
    @Published var colorProfileName: [CGDirectDisplayID: String] = [:]

    var config = ConfigStore.load()

    init() {
        DDCService.tuning = config.ddcTuning
        startObservingScreens()
        PresetService.warmUp { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
        AppDelegate.teardownHiDPI = { [weak self] in self?.teardownHiDPI() }
        PIPController.shared.onConfigChange = { [weak self] key, pipConfig in
            self?.savePIPConfig(key: key, pipConfig)
        }
        if config.restoreOnLaunch { reconnectOrphansIfNeeded(); restoreSaved(); restorePIPs() }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.guardArmed = true
        }
        HotkeyService.setBrightnessHook = { [weak self] id, value in
            self?.setBrightness(id, value)
        }
    }

    func displayConfig(_ d: DisplayInfo) -> DisplayConfig {
        config.displays[ConfigStore.stableKey(d)] ?? DisplayConfig()
    }

    func updateDisplayConfig(_ d: DisplayInfo, _ mutate: (inout DisplayConfig) -> Void) {
        var dc = displayConfig(d)
        mutate(&dc)
        config.displays[ConfigStore.stableKey(d)] = dc
        ConfigStore.save(config)
        objectWillChange.send()
    }

    func refresh() {
        displays = DisplayManager.onlineDisplays()
        for d in displays where !VirtualDisplayService.shared.isVirtual(d.id) {
            let key = ConfigStore.stableKey(d)
            if config.displays[key]?.lastDisplayID != d.id {
                var dc = config.displays[key] ?? DisplayConfig()
                dc.lastDisplayID = d.id
                config.displays[key] = dc
                debounced(0) { self.persist() }
            }
        }
        for d in displays {
            if brightness[d.id] == nil {
                brightness[d.id] = BrightnessService.combined(d.id, switchpoint: displayConfig(d).combinedSwitchpoint)
            }
            if color[d.id] == nil { color[d.id] = ColorService.applied[d.id] ?? .neutral }
            if upscalingOn[d.id] == nil { upscalingOn[d.id] = displayConfig(d).upscalingEnabled }
            if presets[d.id] == nil { presets[d.id] = PresetService.presets(for: d.id) }
            let nowActive = PresetService.activePresetIndex(d.id)
            let changedOutside = activePreset[d.id] != nil && activePreset[d.id] != nowActive
            activePreset[d.id] = nowActive
            if changedOutside { afterPresetChange(d) }
            if config.restoreOnLaunch { applyHDRIfNeeded(d) }
            hiDPIToggle[d.id] = HiDPIToggleService.state(d.id)
            notchSupported[d.id] = NotchService.isSupported(d)
            ambientSupported[d.id] = AmbientService.isSupported(d.id)
            colorProfileName[d.id] = ColorProfileService.currentProfile(d.id)?.name
        }
        let anyEDR = displays.contains { upscalingOn[$0.id] == true && UpscalingService.potentialHeadroom($0.id) > 1.01 }
        UpscalingService.shared.setEDRPipeline(active: anyEDR)
    }

    func combinedMax(_ d: DisplayInfo) -> Float {
        guard upscalingOn[d.id] == true else { return 1 }
        let cap = displayConfig(d).maxBoostPercent / 100
        switch UpscalingService.mode(d.id) {
        case .edr: return min(max(BrightnessService.combinedMax(d.id, upscalingOn: true), 1), cap)
        case .sdrBoost: return max(cap, 1)
        }
    }

    func setUpscaling(_ d: DisplayInfo, _ on: Bool) {
        upscalingOn[d.id] = on
        updateDisplayConfig(d) { $0.upscalingEnabled = on }
        UpscalingService.shared.setEDRPipeline(active: upscalingOn.values.contains(true))
        if !on, let v = brightness[d.id], v > 1 { setBrightness(d.id, 1) }
    }

    private func restoreSaved() {
        for d in displays {
            guard let saved = config.displays[ConfigStore.stableKey(d)] else { continue }
            if saved.color.boost > 1.001 {
                setBrightness(d.id, saved.color.boost)
                continue
            }
            if !saved.color.isNeutral {
                color[d.id] = saved.color
                ColorService.apply(d.id, saved.color)
            }
            if let b = saved.lastBrightness { setBrightness(d.id, b) }
        }
        restoreHiDPIVirtualIfNeeded()
    }

    func reconnectOrphansIfNeeded() {
        guard SystemService.disconnectAvailable else { return }
        let saved = config.displays.mapValues { (lastID: $0.lastDisplayID, soft: $0.softDisconnected) }
        let online = DisplayManager.onlineDisplays()
        let cands = ReconnectPolicy.candidates(
            saved: saved,
            onlineKeys: Set(online.map(ConfigStore.stableKey)),
            onlineIDs: Set(online.map(\.id)))
        for c in cands where SystemService.setConnected(c.displayID, true) {
            NSLog("[reconnect] religado %@ (id %u)", c.key, c.displayID)
        }
    }

    func reconnect(key: String) {
        guard var dc = config.displays[key], let id = dc.lastDisplayID else { return }
        dc.softDisconnected = false
        config.displays[key] = dc
        persist()
        _ = SystemService.setConnected(CGDirectDisplayID(id), true)
    }

    var softDisconnectedKeys: [String] {
        let onlineKeys = Set(displays.map(ConfigStore.stableKey))
        return config.displays.filter { $0.value.softDisconnected && !onlineKeys.contains($0.key) }.map(\.key).sorted()
    }

    func markSoftDisconnected(_ d: DisplayInfo) {
        updateDisplayConfig(d) { $0.softDisconnected = true; $0.lastDisplayID = d.id }
    }

    private func restoreHiDPIVirtualIfNeeded() {
        for d in displays
        where config.displays[ConfigStore.stableKey(d)]?.hiDPIVirtual == true
            && !HiDPIService.isActive(d.id)
            && !hiDPIEnabling.contains(d.id)
            && !VirtualDisplayService.shared.isVirtual(d.id) {
            setHiDPIVirtual(d, true, userInitiated: false)
        }
    }

    private func applyHDRIfNeeded(_ d: DisplayInfo) {
        guard PresetService.hasHDRModes(d.id) else { return }
        let saved = config.displays[ConfigStore.stableKey(d)]?.hdr
        let current = SystemService.hdrEnabled(d.id)
        guard let target = HDRPolicy.shouldApply(saved: saved, current: current) else { return }
        _ = SystemService.setHDR(d.id, target)
    }

    func persist() {
        for d in displays {
            var dc = config.displays[ConfigStore.stableKey(d)] ?? DisplayConfig()
            dc.color = color[d.id] ?? .neutral
            dc.lastBrightness = brightness[d.id]
            config.displays[ConfigStore.stableKey(d)] = dc
        }
        ConfigStore.save(config)
    }

    private var pending: [CGDirectDisplayID: Task<Void, Never>] = [:]

    private func debounced(_ id: CGDirectDisplayID, _ work: @escaping @MainActor () -> Void) {
        pending[id]?.cancel()
        pending[id] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            work()
        }
    }

    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) {
        let ceiling = displays.first(where: { $0.id == id }).map { combinedMax($0) } ?? 1
        let value = min(value, ceiling)
        brightness[id] = value
        let dc = displays.first(where: { $0.id == id }).map { displayConfig($0) } ?? DisplayConfig()
        debounced(id) {
            BrightnessService.setCombined(id, value, switchpoint: dc.combinedSwitchpoint,
                                          minHardware: dc.minHardwareBrightness)
            self.color[id] = ColorService.applied[id] ?? self.color[id]
            self.persist()
        }
    }

    func setPreset(_ d: DisplayInfo, index: Int) {
        ColorService.reset(d.id)
        guard PresetService.setPreset(d.id, index: index) else { return }
        activePreset[d.id] = index
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.afterPresetChange(d)
        }
    }

    private func afterPresetChange(_ d: DisplayInfo) {
        ColorService.invalidateFactoryTable(d.id)
        brightness[d.id] = nil
        refresh()
        if let adj = color[d.id], !adj.isNeutral {
            ColorService.apply(d.id, adj)
        }
        if let v = brightness[d.id], v > combinedMax(d) {
            setBrightness(d.id, combinedMax(d))
        }
    }

    private var guardArmed = false
    private var lastReapply: [CGDirectDisplayID: Date] = [:]
    private var reapplyRetries: [CGDirectDisplayID: Int] = [:]

    func layoutProtected(_ d: DisplayInfo) -> Bool { displayConfig(d).protectLayout }

    func setLayoutProtection(_ d: DisplayInfo, _ on: Bool) {
        updateDisplayConfig(d) {
            $0.protectLayout = on
            $0.protectedSnapshot = on ? LayoutGuardService.snapshot(d.id) : nil
        }
        lastReapply[d.id] = nil
        reapplyRetries[d.id] = 0
    }

    func userChangedLayout(_ d: DisplayInfo) {
        refresh()
        guard displayConfig(d).protectLayout else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            self.updateDisplayConfig(d) { $0.protectedSnapshot = LayoutGuardService.snapshot(d.id) }
            self.lastReapply[d.id] = nil
            self.reapplyRetries[d.id] = 0
        }
    }

    func enforceProtection() {
        guard guardArmed else { return }
        for d in displays {
            guard rotationPending[d.id] == nil else { continue }
            let cfg = displayConfig(d)
            guard cfg.protectLayout, let saved = cfg.protectedSnapshot else { continue }
            let current = LayoutGuardService.snapshot(d.id)
            var drift = LayoutGuard.diff(saved: saved, current: current)
            if HiDPIService.isActive(d.id) { drift.remove(.mirror) }
            guard !drift.isEmpty else {
                reapplyRetries[d.id] = 0
                continue
            }
            guard LayoutGuard.shouldReapply(lastReapply: lastReapply[d.id]) else { continue }
            let retries = reapplyRetries[d.id] ?? 0
            guard retries <= 1 else { continue }
            lastReapply[d.id] = Date()
            reapplyRetries[d.id] = retries + 1
            LayoutGuardService.reapply(d.id, saved: saved, fields: drift)
        }
    }

    @Published var rotationPending: [CGDirectDisplayID: (previous: Int, seconds: Int)] = [:]
    private var rotationTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]

    func setRotation(_ d: DisplayInfo, degrees: Int) {
        let previous = rotationPending[d.id]?.previous ?? RotationService.current(d.id)
        guard degrees != RotationService.current(d.id) else { return }
        guard RotationService.set(d.id, degrees: degrees) else { return }
        rotationTasks[d.id]?.cancel()
        rotationPending[d.id] = (previous, 10)
        rotationTasks[d.id] = Task { @MainActor [weak self] in
            for remaining in stride(from: 9, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.rotationPending[d.id] != nil else { return }
                self.rotationPending[d.id]?.seconds = remaining
            }
            self?.revertRotation(d)
        }
    }

    func keepRotation(_ d: DisplayInfo) {
        rotationTasks[d.id]?.cancel()
        rotationTasks[d.id] = nil
        rotationPending[d.id] = nil
        userChangedLayout(d)
    }

    func revertRotation(_ d: DisplayInfo) {
        rotationTasks[d.id]?.cancel()
        rotationTasks[d.id] = nil
        guard let pending = rotationPending.removeValue(forKey: d.id) else { return }
        RotationService.set(d.id, degrees: pending.previous)
        refresh()
    }

    func showAllModes(_ d: DisplayInfo) -> Bool { displayConfig(d).showAllModes }

    func setShowAllModes(_ d: DisplayInfo, _ on: Bool) {
        updateDisplayConfig(d) { $0.showAllModes = on }
    }

    func hiDPIVirtualOn(_ d: DisplayInfo) -> Bool {
        HiDPIService.isActive(d.id) || displayConfig(d).hiDPIVirtual
    }

    func setHiDPIVirtual(_ d: DisplayInfo, _ on: Bool, sharp: Bool? = nil, userInitiated: Bool = true) {
        let wantSharp = sharp ?? displayConfig(d).hiDPISupersample
        if on {
            if HiDPIService.isActive(d.id) {
                guard wantSharp != displayConfig(d).hiDPISupersample else { return }
                HiDPIService.disable(d.id, restoreModeID: displayConfig(d).previousModeID)
            }
            hiDPIEnabling.insert(d.id)
            Task { @MainActor in
                defer { hiDPIEnabling.remove(d.id) }
                guard let previous = await HiDPIService.enable(d.id, name: d.name, supersample: wantSharp) else {
                    if userInitiated { updateDisplayConfig(d) { $0.hiDPIVirtual = false } }
                    return
                }
                updateDisplayConfig(d) {
                    $0.hiDPIVirtual = true
                    $0.hiDPISupersample = wantSharp
                    $0.previousModeID = previous
                }
                refresh()
            }
        } else {
            HiDPIService.disable(d.id, restoreModeID: displayConfig(d).previousModeID)
            updateDisplayConfig(d) { $0.hiDPIVirtual = false }
            refresh()
        }
    }

    func hiDPISharpOn(_ d: DisplayInfo) -> Bool {
        HiDPIService.isActive(d.id) && displayConfig(d).hiDPISupersample
    }

    private func savePIPConfig(key: String, _ pipConfig: PIPConfig?) {
        var dc = config.displays[key] ?? DisplayConfig()
        dc.pip = pipConfig
        config.displays[key] = dc
        debounced(0) { self.persist() }
    }

    private func restorePIPs() {
        guard ScreenCapturePermission.granted else { return }
        for anchor in displays {
            let key = ConfigStore.stableKey(anchor)
            guard let pipConfig = config.displays[key]?.pip, pipConfig.autoStart else { continue }
            guard let source = displays.first(where: {
                ConfigStore.stableKey($0) == pipConfig.sourceDisplayKey
            }) else { continue }
            _ = PIPController.shared.open(anchorKey: key, source: source.id,
                                          config: pipConfig, askPermission: false)
        }
    }

    func teardownHiDPI() {
        for d in displays where HiDPIService.isActive(d.id) {
            HiDPIService.disable(d.id, restoreModeID: displayConfig(d).previousModeID)
        }
    }

    func setColor(_ id: CGDirectDisplayID, _ transform: (inout ColorAdjustments) -> Void) {
        var adj = color[id] ?? .neutral
        transform(&adj)
        color[id] = adj
        ColorService.apply(id, adj)
        debounced(id) { self.persist() }
    }
}
