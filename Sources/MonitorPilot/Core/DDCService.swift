import Foundation
import CoreGraphics
import IOKit

/// DDC/CI via IOAVService (Apple Silicon) — receita do m1ddc/BetterDisplay.
/// Fala I2C direto com o monitor externo no endereço 0x37.
/// Experimental: sem monitor externo conectado, tudo aqui retorna nil/false.
enum DDCService {
    enum VCP: UInt8 {
        case brightness = 0x10
        case contrast = 0x12
        case volume = 0x62
        case mute = 0x8D
        case inputSource = 0x60
        case power = 0xD6
    }

    struct Reading { let current: UInt16; let max: UInt16 }

    private static let i2cAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    /// Ajuste fino do protocolo (equivalente às configs avançadas de DDC do BetterDisplay).
    struct Tuning: Codable, Equatable {
        var writeAttempts: Int = 3        // tentativas em caso de falha
        var sendsPerCommand: Int = 1      // envios por comando (monitores surdos)
        var delayBetweenMs: UInt32 = 20   // atraso entre tentativas/envios
        var readReplyWaitMs: UInt32 = 40  // espera pela resposta na leitura
        var ignoreReadChecksum: Bool = false
    }
    static var tuning = Tuning()

    // MARK: Localização do serviço AV do display externo

    private static var cachedServices: [CGDirectDisplayID: CFTypeRef] = [:]

    private static func avService(for id: CGDirectDisplayID) -> CFTypeRef? {
        if let cached = cachedServices[id] { return cached }
        guard CGDisplayIsBuiltin(id) == 0,
              let create = PrivateAPI.ioavCreateWithService else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var externals: [io_service_t] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let location = IORegistryEntryCreateCFProperty(
                service, "Location" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String
            if location == "External" {
                externals.append(service)
            } else {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }
        defer { externals.forEach { IOObjectRelease($0) } }
        guard let port = portService(for: id, among: externals) else { return nil }
        if let av = create(kCFAllocatorDefault, port)?.takeRetainedValue() {
            cachedServices[id] = av
            return av
        }
        return nil
    }

    /// Com 1 externo, é ele. Com vários, casa pelo papel DCPEXT<n> do proxy ×
    /// ConnectionMapping (DDCPortMapper). Sem casamento único, falha alto —
    /// escrever no chute mexeria no monitor ERRADO.
    private static func portService(for id: CGDirectDisplayID, among externals: [io_service_t]) -> io_service_t? {
        if externals.count == 1 { return externals[0] }
        guard let wanted = DDCPortMapper.role(
            forModel: CGDisplayModelNumber(id),
            name: DisplayManager.displayName(id),
            in: DDCPortMapper.connections()
        ) else { return nil }
        let matches = externals.filter { DDCPortMapper.role(ofProxy: $0) == wanted }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Diagnóstico `ddc ports`: cada proxy externo → papel DCPEXT → display casado.
    static func portReport() -> [String] {
        var out: [String] = []
        let conns = DDCPortMapper.connections()
        out.append("ConnectionMapping: " + (conns.isEmpty ? "(vazio)" : conns.map {
            "\($0.role)=\($0.productName) pid=0x\(String($0.productID, radix: 16))" }.joined(separator: " · ")))
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return out + ["sem DCPAVServiceProxy"]
        }
        defer { IOObjectRelease(iterator) }
        let displays = DisplayManager.onlineDisplays()
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let location = IORegistryEntryCreateCFProperty(
                service, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            let role = DDCPortMapper.role(ofProxy: service) ?? "?"
            let owner = displays.first {
                DDCPortMapper.role(forModel: $0.model, name: $0.name, in: conns) == role
            }
            var idBuf: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &idBuf)
            out.append("proxy 0x\(String(idBuf, radix: 16)) loc=\(location ?? "-") papel=\(role) → " +
                       (owner.map { "\($0.id) \($0.name)" } ?? "(nenhum display)"))
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return out
    }

    // MARK: Protocolo DDC/CI

    static func write(_ id: CGDirectDisplayID, vcp: VCP, value: UInt16) -> Bool {
        guard let av = avService(for: id),
              let writeI2C = PrivateAPI.ioavWriteI2C else { return false }
        var packet: [UInt8] = [
            0x84, 0x03, vcp.rawValue,
            UInt8(value >> 8), UInt8(value & 0xFF), 0,
        ]
        packet[5] = checksum(UInt8(0x6E ^ dataAddress), packet, upTo: 5)
        var attempts = 0
        while attempts < max(tuning.writeAttempts, 1) {
            attempts += 1
            var ok = false
            for send in 0..<max(tuning.sendsPerCommand, 1) {
                if send > 0 { usleep(tuning.delayBetweenMs * 1000) }
                ok = packet.withUnsafeMutableBytes { buf in
                    writeI2C(av, i2cAddress, dataAddress, buf.baseAddress!, UInt32(buf.count)) == 0
                }
            }
            if ok { return true }
            usleep(tuning.delayBetweenMs * 1000)
        }
        return false
    }

    static func read(_ id: CGDirectDisplayID, vcp: VCP) -> Reading? {
        guard let av = avService(for: id),
              let writeI2C = PrivateAPI.ioavWriteI2C,
              let readI2C = PrivateAPI.ioavReadI2C else { return nil }
        var request: [UInt8] = [0x82, 0x01, vcp.rawValue, 0]
        request[3] = checksum(UInt8(0x6E ^ dataAddress), request, upTo: 3)
        let wrote = request.withUnsafeMutableBytes { buf in
            writeI2C(av, i2cAddress, dataAddress, buf.baseAddress!, UInt32(buf.count)) == 0
        }
        guard wrote else { return nil }
        usleep(tuning.readReplyWaitMs * 1000)
        var reply = [UInt8](repeating: 0, count: 12)
        let rc = reply.withUnsafeMutableBytes { buf in
            readI2C(av, i2cAddress, dataAddress, buf.baseAddress!, UInt32(buf.count))
        }
        if ProcessInfo.processInfo.environment["MONITORPILOT_DDC_DEBUG"] != nil {
            FileHandle.standardError.write("ddc read rc=\(rc) reply=\(reply.map { String(format: "%02x", $0) }.joined(separator: " "))\n".data(using: .utf8)!)
        }
        guard rc == 0 else { return nil }
        if !tuning.ignoreReadChecksum {
            guard reply[2] == 0x02, reply[4] == vcp.rawValue else { return nil }
        }
        return Reading(
            current: UInt16(reply[8]) << 8 | UInt16(reply[9]),
            max: UInt16(reply[6]) << 8 | UInt16(reply[7])
        )
    }

    private static var cachedMax: [String: UInt16] = [:]

    /// Max reportado pelo monitor para um VCP (cacheado por display+vcp).
    static func maxValue(_ id: CGDirectDisplayID, vcp: VCP) -> UInt16? {
        let key = "\(id):\(vcp.rawValue)"
        if let cached = cachedMax[key] { return cached }
        guard let reading = read(id, vcp: vcp) else { return nil }
        cachedMax[key] = reading.max
        return reading.max
    }

    static func checksum(_ seed: UInt8, _ bytes: [UInt8], upTo end: Int) -> UInt8 {
        var chk = seed
        for i in 0..<end { chk ^= bytes[i] }
        return chk
    }
}
