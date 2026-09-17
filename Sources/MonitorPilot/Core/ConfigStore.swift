import Foundation
import CoreGraphics

struct DisplayConfig: Codable {
    var color: ColorAdjustments = .neutral
    var lastBrightness: Float?
    var upscalingEnabled: Bool = false
    var combinedSwitchpoint: Float = 0.5
    var maxBoostPercent: Float = 160
    var minHardwareBrightness: Float = 0.05
    var hdr: Bool?
    var showAllModes: Bool = false
    var hiDPIVirtual: Bool = false
    var hiDPISupersample: Bool = false
    var previousModeID: Int32?
    var protectLayout: Bool = false
    var protectedSnapshot: DisplaySnapshot?
    var pip: PIPConfig?
    var lastDisplayID: UInt32?
    var softDisconnected: Bool = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .neutral
        lastBrightness = try c.decodeIfPresent(Float.self, forKey: .lastBrightness)
        upscalingEnabled = try c.decodeIfPresent(Bool.self, forKey: .upscalingEnabled) ?? false
        combinedSwitchpoint = try c.decodeIfPresent(Float.self, forKey: .combinedSwitchpoint) ?? 0.5
        maxBoostPercent = try c.decodeIfPresent(Float.self, forKey: .maxBoostPercent) ?? 160
        minHardwareBrightness = try c.decodeIfPresent(Float.self, forKey: .minHardwareBrightness) ?? 0.05
        hdr = try c.decodeIfPresent(Bool.self, forKey: .hdr)
        showAllModes = try c.decodeIfPresent(Bool.self, forKey: .showAllModes) ?? false
        hiDPIVirtual = try c.decodeIfPresent(Bool.self, forKey: .hiDPIVirtual) ?? false
        hiDPISupersample = try c.decodeIfPresent(Bool.self, forKey: .hiDPISupersample) ?? false
        previousModeID = try c.decodeIfPresent(Int32.self, forKey: .previousModeID)
        protectLayout = try c.decodeIfPresent(Bool.self, forKey: .protectLayout) ?? false
        protectedSnapshot = try c.decodeIfPresent(DisplaySnapshot.self, forKey: .protectedSnapshot)
        pip = try c.decodeIfPresent(PIPConfig.self, forKey: .pip)
        lastDisplayID = try c.decodeIfPresent(UInt32.self, forKey: .lastDisplayID)
        softDisconnected = try c.decodeIfPresent(Bool.self, forKey: .softDisconnected) ?? false
    }
}

struct PIPConfig: Codable {
    var sourceDisplayKey: String = ""
    var frame: CGRect = CGRect(x: 60, y: 60, width: 480, height: 270)
    var alpha: Double = 1
    var clickThrough: Bool = false
    var alwaysOnTop: Bool = true
    var showCursor: Bool = false
    var autoStart: Bool = false
    var crop: CGRect?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceDisplayKey = try c.decodeIfPresent(String.self, forKey: .sourceDisplayKey) ?? ""
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame)
            ?? CGRect(x: 60, y: 60, width: 480, height: 270)
        alpha = try c.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        clickThrough = try c.decodeIfPresent(Bool.self, forKey: .clickThrough) ?? false
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? true
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? false
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        crop = try c.decodeIfPresent(CGRect.self, forKey: .crop)
    }
}

struct AppConfig: Codable {
    var displays: [String: DisplayConfig] = [:]
    var virtualScreens: [VirtualScreenConfig] = []
    var restoreOnLaunch: Bool = true
    var hotkeysEnabled: Bool = true
    var ddcTuning: DDCService.Tuning = .init()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displays = try c.decodeIfPresent([String: DisplayConfig].self, forKey: .displays) ?? [:]
        virtualScreens = try c.decodeIfPresent([VirtualScreenConfig].self, forKey: .virtualScreens) ?? []
        restoreOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .restoreOnLaunch) ?? true
        hotkeysEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeysEnabled) ?? true
        ddcTuning = try c.decodeIfPresent(DDCService.Tuning.self, forKey: .ddcTuning) ?? .init()
    }
}

struct VirtualScreenConfig: Codable, Identifiable {
    var id = UUID()
    var name: String
    var aspectWidth: Int
    var aspectHeight: Int
    var hiDPI: Bool = true
    var autoConnect: Bool = false
}

enum ConfigStore {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/monitorpilot/config.json")

    static func stableKey(_ d: DisplayInfo) -> String { "\(d.vendor):\(d.model):\(d.serial)" }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    static func save(_ config: AppConfig) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? encoder.encode(config))?.write(to: url)
    }
}
