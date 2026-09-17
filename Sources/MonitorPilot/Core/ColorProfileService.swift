import Foundation
import CoreGraphics
import ApplicationServices

/// "Modo de cor": perfis ICC do display, tudo por ColorSync PÚBLICO.
/// O device id é o UUID do display (CGDisplayCreateUUIDFromDisplayID).
struct ColorProfile: Identifiable, Hashable {
    let name: String
    let url: URL
    var id: URL { url }
}

enum ColorProfileService {
    // As constantes do ColorSync vêm ora como CFString, ora como Unmanaged —
    // estes overloads normalizam pra String e o dicionário vira [String: Any].
    private static func str(_ v: CFString) -> String { v as String }
    private static func str(_ v: Unmanaged<CFString>) -> String { v.takeUnretainedValue() as String }
    private static func cls(_ v: CFString) -> CFString { v }
    private static func cls(_ v: Unmanaged<CFString>) -> CFString { v.takeUnretainedValue() }

    // MARK: leitura

    /// Cache: varrer os ICC do disco custa I/O e a lista quase nunca muda.
    private nonisolated(unsafe) static var cache: [ColorProfile]?

    /// Perfis de monitor instalados no sistema (classe "mntr").
    static func installedProfiles() -> [ColorProfile] {
        if let cache { return cache }
        let list = scanInstalledProfiles()
        cache = list
        return list
    }

    /// Esquece o cache (novo perfil instalado).
    static func invalidateCache() { cache = nil }

    private static func scanInstalledProfiles() -> [ColorProfile] {
        final class Box { var items: [ColorProfile] = [] }
        let box = Box()
        var seed: UInt32 = 0
        let userInfo = Unmanaged.passUnretained(box).toOpaque()
        ColorSyncIterateInstalledProfiles({ info, refcon in
            guard let refcon,
                  let dict = info as? [String: Any],
                  let url = dict[ColorProfileService.str(kColorSyncProfileURL)] as? URL
            else { return true }
            let klass = dict[ColorProfileService.str(kColorSyncProfileClass)]
            let isMonitor = (klass as? String) == "mntr"
                || (klass as? NSNumber)?.uint32Value == 0x6D6E_7472  // 'mntr'
            guard isMonitor else { return true }
            let name = (dict[ColorProfileService.str(kColorSyncProfileDescription)] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let box = Unmanaged<Box>.fromOpaque(refcon).takeUnretainedValue()
            box.items.append(ColorProfile(name: name, url: url))
            return true
        }, &seed, userInfo, nil)
        return box.items
            .reduce(into: [ColorProfile]()) { acc, p in if !acc.contains(p) { acc.append(p) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func deviceID(_ id: CGDirectDisplayID) -> CFUUID? {
        CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
    }

    private static func deviceInfo(_ id: CGDirectDisplayID) -> [String: Any]? {
        guard let uuid = deviceID(id),
              let info = ColorSyncDeviceCopyDeviceInfo(cls(kColorSyncDisplayDeviceClass), uuid)
        else { return nil }
        return info.takeRetainedValue() as? [String: Any]
    }

    /// Perfil ativo (custom se houver, senão o de fábrica).
    static func currentProfile(_ id: CGDirectDisplayID) -> ColorProfile? {
        guard let info = deviceInfo(id) else { return nil }
        func url(_ key: String) -> URL? {
            guard let group = info[key] as? [String: Any] else { return nil }
            let entry = (group[str(kColorSyncDeviceDefaultProfileID)] as? [String: Any])
                ?? group.values.compactMap { $0 as? [String: Any] }.first
            return entry?[str(kColorSyncDeviceProfileURL)] as? URL
        }
        guard let u = url(str(kColorSyncCustomProfiles)) ?? url(str(kColorSyncFactoryProfiles))
        else { return nil }
        let name = installedProfiles().first { $0.url == u }?.name
            ?? u.deletingPathExtension().lastPathComponent
        return ColorProfile(name: name, url: u)
    }

    static func isFactory(_ id: CGDirectDisplayID) -> Bool {
        guard let info = deviceInfo(id),
              let custom = info[str(kColorSyncCustomProfiles)] as? [String: Any]
        else { return true }
        return custom.isEmpty
    }

    // MARK: escrita (reversível — "Padrão de fábrica" volta ao original)

    @discardableResult
    static func setProfile(_ id: CGDirectDisplayID, url: URL) -> Bool {
        guard let uuid = deviceID(id) else { return false }
        let profiles = [str(kColorSyncDeviceDefaultProfileID): url as CFURL] as CFDictionary
        return ColorSyncDeviceSetCustomProfiles(cls(kColorSyncDisplayDeviceClass), uuid, profiles)
    }

    /// Volta pro perfil de fábrica do display.
    @discardableResult
    static func resetToFactory(_ id: CGDirectDisplayID) -> Bool {
        guard let uuid = deviceID(id) else { return false }
        let profiles = [str(kColorSyncDeviceDefaultProfileID): kCFNull as Any] as CFDictionary
        return ColorSyncDeviceSetCustomProfiles(cls(kColorSyncDisplayDeviceClass), uuid, profiles)
    }
}
