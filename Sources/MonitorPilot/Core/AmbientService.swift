import Foundation
import CoreGraphics

/// "Brilho Automático" — compensação de luz ambiente (o mesmo toggle de
/// Ajustes › Monitores). Símbolos privados do DisplayServices, resolvidos por
/// dlsym: se sumirem num macOS futuro, a linha aparece desabilitada.
enum AmbientService {
    static var isAvailable: Bool {
        PrivateAPI.dsAmbientEnabled != nil && PrivateAPI.dsSetAmbient != nil
    }

    /// O display tem sensor? (externos normalmente não)
    static func isSupported(_ id: CGDirectDisplayID) -> Bool {
        guard isAvailable else { return false }
        if let has = PrivateAPI.dsHasAmbient { return has(id) }
        return enabled(id) != nil
    }

    static func enabled(_ id: CGDirectDisplayID) -> Bool? {
        guard let read = PrivateAPI.dsAmbientEnabled else { return nil }
        var value = false
        guard read(id, &value) == 0 else { return nil }
        return value
    }

    @discardableResult
    static func set(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        guard let write = PrivateAPI.dsSetAmbient else { return false }
        return write(id, on) == 0
    }
}
