import Foundation
import CoreGraphics
import ObjectiveC

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

    private nonisolated(unsafe) static var cachedManager: NSObject?
    private static let warmupQueue = DispatchQueue(label: "monitorpilot.preset.warmup")

    static func warmUp(then onReady: (@Sendable () -> Void)? = nil) {
        warmupQueue.async {
            guard cachedManager == nil, available,
                  let cls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return }
            let mgr = cls.init()
            cachedManager = mgr
            onReady?()
        }
    }

    static func warmUpBlocking() {
        guard cachedManager == nil, available,
              let cls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return }
        cachedManager = cls.init()
    }

    static func manager() -> NSObject? { cachedManager }

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

    static func display(for id: CGDirectDisplayID) -> NSObject? {
        guard let mgr = manager() else { return nil }
        return mpDisplay(mgr, id)
    }

    static func hasHDRModes(_ id: CGDirectDisplayID) -> Bool {
        guard let d = display(for: id) else { return false }
        return (d.value(forKey: "hasHDRModes") as? Bool) ?? false
    }

    static func preferHDRModes(_ id: CGDirectDisplayID) -> Bool? {
        guard let d = display(for: id) else { return nil }
        return d.value(forKey: "preferHDRModes") as? Bool
    }

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

    @discardableResult
    static func setPreset(_ id: CGDirectDisplayID, index: Int) -> Bool {
        guard let mgr = manager(), let d = mpDisplay(mgr, id),
              let list = d.value(forKey: "presets") as? [NSObject],
              list.indices.contains(index),
              (list[index].value(forKey: "isValid") as? Bool) == true
        else { return false }
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
