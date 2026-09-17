import Foundation
import CoreGraphics
import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let sizePixels: CGSize
}

enum DisplayManager {
    static func onlineDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            DisplayInfo(
                id: id,
                name: displayName(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id),
                sizePixels: CGSize(
                    width: CGDisplayPixelsWide(id),
                    height: CGDisplayPixelsHigh(id)
                )
            )
        }
    }

    static func displayName(_ id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let num = screen.deviceDescription[key] as? NSNumber,
               num.uint32Value == id {
                return screen.localizedName
            }
        }
        return CGDisplayIsBuiltin(id) != 0 ? "Tela interna" : "Display \(id)"
    }

    static func resolve(_ selector: String?) -> DisplayInfo? {
        let all = onlineDisplays()
        guard let selector, !selector.isEmpty else {
            return all.first(where: \.isMain) ?? all.first
        }
        if let numeric = UInt32(selector),
           let byID = all.first(where: { $0.id == numeric }) {
            return byID
        }
        return all.first { $0.name.localizedCaseInsensitiveContains(selector) }
    }
}
