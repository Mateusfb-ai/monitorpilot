import Foundation
import CoreGraphics

enum ReconnectPolicy {
    struct Candidate: Equatable {
        let key: String
        let displayID: CGDirectDisplayID
    }

    static func candidates(saved: [String: (lastID: UInt32?, soft: Bool)],
                           onlineKeys: Set<String>, onlineIDs: Set<CGDirectDisplayID>) -> [Candidate] {
        saved.compactMap { key, v in
            guard !onlineKeys.contains(key), !v.soft, let id = v.lastID,
                  !onlineIDs.contains(CGDirectDisplayID(id)) else { return nil }
            return Candidate(key: key, displayID: CGDirectDisplayID(id))
        }.sorted { $0.key < $1.key }
    }
}
