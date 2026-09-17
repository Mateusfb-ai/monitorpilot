import Foundation
import CoreGraphics
import IOKit

enum DDCPortMapper {
    struct Connection: Equatable {
        let role: String
        let productID: UInt32
        let productName: String
    }

    static func role(inEntryName name: String) -> String? {
        guard let r = name.range(of: #"(?i)dcpext\d+"#, options: .regularExpression) else { return nil }
        return name[r].uppercased()
    }

    static func swapped(_ v: UInt32) -> UInt32 {
        ((v & 0xFF) << 8) | ((v >> 8) & 0xFF)
    }

    static func role(forModel model: UInt32, name: String, in connections: [Connection]) -> String? {
        let byModel = connections.filter {
            $0.productID == model || $0.productID == swapped(model)
        }
        if byModel.count == 1 { return byModel[0].role }
        let byName = (byModel.isEmpty ? connections : byModel).filter {
            !$0.productName.isEmpty && name.localizedCaseInsensitiveContains($0.productName)
        }
        return byName.count == 1 ? byName[0].role : nil
    }

    static func connections() -> [Connection] {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleDisplayConnectionManager"))
        guard service != 0 else { return [] }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(
            service, "ConnectionMapping" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return raw.compactMap { d in
            guard let role = d["role"] as? String else { return nil }
            let pid = (d["ProductID"] as? NSNumber)?.uint32Value ?? 0
            return Connection(role: role, productID: pid,
                              productName: d["ProductName"] as? String ?? "")
        }
    }

    static func role(ofProxy service: io_service_t) -> String? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<12 {
            var buf = [CChar](repeating: 0, count: 128)
            if IORegistryEntryGetName(current, &buf) == KERN_SUCCESS,
               let r = role(inEntryName: String(cString: buf)) {
                return r
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(current)
            current = parent
        }
        return nil
    }
}
