import Foundation
import AppKit
import CoreGraphics
import IOKit.pwr_mgt

enum SystemService {

    private static let blueLight: NSObject? = {
        (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
    }()

    static var nightShiftAvailable: Bool { blueLight != nil }

    static func setNightShift(enabled: Bool) -> Bool {
        guard let client = blueLight else { return false }
        typealias SetEnabled = @convention(c) (NSObject, Selector, Bool) -> Bool
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel) else { return false }
        return unsafeBitCast(client.method(for: sel), to: SetEnabled.self)(client, sel, enabled)
    }

    static func setNightShiftStrength(_ strength: Float) -> Bool {
        guard let client = blueLight else { return false }
        typealias SetStrength = @convention(c) (NSObject, Selector, Float, Bool) -> Bool
        let sel = NSSelectorFromString("setStrength:commit:")
        guard client.responds(to: sel) else { return false }
        return unsafeBitCast(client.method(for: sel), to: SetStrength.self)(client, sel, min(max(strength, 0), 1), true)
    }

    @discardableResult
    static func setMirror(_ display: CGDirectDisplayID, of master: CGDirectDisplayID?) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let target = master ?? kCGNullDirectDisplay
        guard CGConfigureDisplayMirrorOfDisplay(config, display, target) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    static func mirrorMaster(_ display: CGDirectDisplayID) -> CGDirectDisplayID? {
        let master = CGDisplayMirrorsDisplay(display)
        return master == kCGNullDirectDisplay ? nil : master
    }

    static var disconnectAvailable: Bool { PrivateAPI.cgsConfigureDisplayEnabled != nil }

    @discardableResult
    static func setConnected(_ display: CGDirectDisplayID, _ connected: Bool) -> Bool {
        guard let configure = PrivateAPI.cgsConfigureDisplayEnabled else { return false }
        if !connected {
            let online = DisplayManager.onlineDisplays()
            guard online.count > 1 else { return false }
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard configure(config, display, connected) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    static func hdrSupported(_ display: CGDirectDisplayID) -> Bool {
        if PresetService.display(for: display) != nil { return PresetService.hasHDRModes(display) }
        guard let cid = PrivateAPI.slsMainConnectionID?(),
              let supported = PrivateAPI.slsDisplaySupportsHDRMode else { return false }
        return supported(cid, display)
    }

    static func hdrEnabled(_ display: CGDirectDisplayID) -> Bool {
        if let v = PresetService.preferHDRModes(display) { return v }
        guard let cid = PrivateAPI.slsMainConnectionID?(),
              let enabled = PrivateAPI.slsDisplayIsHDRModeEnabled else { return false }
        return enabled(cid, display)
    }

    @discardableResult
    static func setHDR(_ display: CGDirectDisplayID, _ on: Bool) -> Bool {
        if PresetService.display(for: display) != nil {
            return PresetService.setPreferHDRModes(display, on)
        }
        guard let cid = PrivateAPI.slsMainConnectionID?(),
              let set = PrivateAPI.slsDisplaySetHDRModeEnabled else { return false }
        return set(cid, display, on) == 0
    }

    @discardableResult
    static func setMain(_ id: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsMain(id) == 0 else { return true }
        let displays = DisplayManager.onlineDisplays()
        let newMainBounds = CGDisplayBounds(id)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for d in displays {
            let b = CGDisplayBounds(d.id)
            guard CGConfigureDisplayOrigin(
                config, d.id,
                Int32(b.origin.x - newMainBounds.origin.x),
                Int32(b.origin.y - newMainBounds.origin.y)
            ) == .success else {
                CGCancelDisplayConfiguration(config)
                return false
            }
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    @MainActor private static var identifyPanels: [NSPanel] = []

    @MainActor
    static func identifyDisplays() {
        identifyPanels.forEach { $0.orderOut(nil) }
        identifyPanels.removeAll()
        for screen in NSScreen.screens {
            let f = screen.frame
            let panel = NSPanel(
                contentRect: NSRect(x: f.midX - 220, y: f.midY - 60, width: 440, height: 120),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            let label = NSTextField(labelWithString: screen.localizedName)
            label.font = .systemFont(ofSize: 42, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: 0, y: 30, width: 440, height: 60)
            let box = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 120))
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
            box.layer?.cornerRadius = 24
            box.addSubview(label)
            panel.contentView = box
            panel.orderFrontRegardless()
            identifyPanels.append(panel)
        }
        let panels = identifyPanels
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            panels.forEach { $0.orderOut(nil) }
        }
    }

    private static var sleepAssertion: IOPMAssertionID = 0

    @discardableResult
    static func preventSleep(_ prevent: Bool) -> Bool {
        if prevent {
            guard sleepAssertion == 0 else { return true }
            return IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "MonitorPilot: manter display acordado" as CFString,
                &sleepAssertion
            ) == kIOReturnSuccess
        }
        guard sleepAssertion != 0 else { return true }
        IOPMAssertionRelease(sleepAssertion)
        sleepAssertion = 0
        return true
    }

    static var isPreventingSleep: Bool { sleepAssertion != 0 }
}
