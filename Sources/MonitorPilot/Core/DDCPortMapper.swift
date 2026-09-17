import Foundation
import CoreGraphics
import IOKit

/// Mapa displayID → porta DDC (`DCPAVServiceProxy`) com vários monitores externos.
///
/// O IORegistry não liga o proxy ao display diretamente. Duas pistas que ligam:
///   1. O proxy é descendente de `RTBuddy(DCPEXT<n>)` / `iop-dcpext<n>-nub` — o
///      nome do ancestral carrega o papel `DCPEXT<n>`.
///   2. `AppleDisplayConnectionManager.ConnectionMapping` lista, por papel, o
///      `ProductID`/`ProductName` do monitor plugado (verificado no M4: role
///      DCPEXT1 → LG ULTRAFINE, DCPEXT2 → DELL P2722H).
/// O `ProductID` do mapa vem com os bytes trocados em relação a
/// `CGDisplayModelNumber` (LG 0x9D5C ↔ 0x5C9D; DELL 0x4142 ↔ 0x4241).
enum DDCPortMapper {
    struct Connection: Equatable {
        let role: String        // "DCPEXT1"
        let productID: UInt32   // como vem no ConnectionMapping (byte-swapped)
        let productName: String
    }

    /// Papel `DCPEXT<n>` embutido num nome de entrada do registry (`RTBuddy(DCPEXT1)`).
    static func role(inEntryName name: String) -> String? {
        guard let r = name.range(of: #"(?i)dcpext\d+"#, options: .regularExpression) else { return nil }
        return name[r].uppercased()
    }

    /// Bytes trocados do product code (o mapa do DCP e o CG discordam na ordem).
    static func swapped(_ v: UInt32) -> UInt32 {
        ((v & 0xFF) << 8) | ((v >> 8) & 0xFF)
    }

    /// Papel da porta que serve o display de `model`/`name`, ou nil se ambíguo.
    /// Modelo casa em qualquer ordem de byte; nome desempata quando 2 monitores
    /// iguais estão plugados (aí só o nome não resolve — devolve nil, falha alto).
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

    // MARK: IORegistry

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

    /// Papel `DCPEXT<n>` do proxy, subindo pelos ancestrais no plano IOService.
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
