import Foundation
import CoreGraphics

/// Regra pura: quais displays salvos devem ser religados via CGS no boot /
/// hot-plug. Um display que sumiu SEM o dono pedir ("Desconectar (soft)")
/// é o caso do Dell órfão: o MonitorPilot morreu por SIGTERM, a tela virtual
/// que ele espelhava sumiu junto e o macOS deixou o físico offline.
enum ReconnectPolicy {
    struct Candidate: Equatable {
        let key: String
        let displayID: CGDirectDisplayID
    }

    /// `saved`: (chave estável → (lastDisplayID, softDisconnected)); `onlineKeys`:
    /// chaves dos displays online agora; `onlineIDs`: IDs online (um ID salvo que
    /// hoje pertence a OUTRO display online não é religado — evita mexer no LG).
    static func candidates(saved: [String: (lastID: UInt32?, soft: Bool)],
                           onlineKeys: Set<String>, onlineIDs: Set<CGDirectDisplayID>) -> [Candidate] {
        saved.compactMap { key, v in
            guard !onlineKeys.contains(key), !v.soft, let id = v.lastID,
                  !onlineIDs.contains(CGDirectDisplayID(id)) else { return nil }
            return Candidate(key: key, displayID: CGDirectDisplayID(id))
        }.sorted { $0.key < $1.key }
    }
}
