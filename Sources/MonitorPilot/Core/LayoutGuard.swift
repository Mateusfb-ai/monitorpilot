import Foundation
import CoreGraphics

/// Fotografia do estado protegido de um display.
struct DisplaySnapshot: Codable, Equatable {
    var modeID: Int32?
    var originX: Int
    var originY: Int
    var rotation: Int
    var mirrorMaster: UInt32?   // displayID do master, ou nil = sem espelho
}

/// Comparação pura: o que saiu do lugar entre o salvo e o atual.
enum LayoutGuard {
    enum Field: String, CaseIterable {
        case mode, origin, rotation, mirror
    }

    static func diff(saved: DisplaySnapshot, current: DisplaySnapshot) -> Set<Field> {
        var out: Set<Field> = []
        if let m = saved.modeID, m != current.modeID { out.insert(.mode) }
        if saved.originX != current.originX || saved.originY != current.originY { out.insert(.origin) }
        if saved.rotation != current.rotation { out.insert(.rotation) }
        if saved.mirrorMaster != current.mirrorMaster { out.insert(.mirror) }
        return out
    }

    /// Pode reaplicar agora? Nunca briga com o usuário: no máximo 1 correção
    /// por minuto por display.
    static func shouldReapply(lastReapply: Date?, now: Date = Date(), cooldown: TimeInterval = 60) -> Bool {
        guard let lastReapply else { return true }
        return now.timeIntervalSince(lastReapply) >= cooldown
    }
}

@MainActor
enum LayoutGuardService {
    static func snapshot(_ id: CGDirectDisplayID) -> DisplaySnapshot {
        let bounds = CGDisplayBounds(id)
        return DisplaySnapshot(
            modeID: CGDisplayCopyDisplayMode(id)?.ioDisplayModeID,
            originX: Int(bounds.origin.x.rounded()),
            originY: Int(bounds.origin.y.rounded()),
            rotation: RotationService.current(id),
            mirrorMaster: SystemService.mirrorMaster(id))
    }

    /// Reaplica só o que saiu do lugar. Devolve os campos corrigidos.
    @discardableResult
    static func reapply(_ id: CGDirectDisplayID, saved: DisplaySnapshot,
                        fields: Set<LayoutGuard.Field>) -> Set<LayoutGuard.Field>
    {
        var done: Set<LayoutGuard.Field> = []
        if fields.contains(.mode), let modeID = saved.modeID,
           ModeService.setMode(id, modeID: modeID) { done.insert(.mode) }
        if fields.contains(.rotation), RotationService.set(id, degrees: saved.rotation) {
            done.insert(.rotation)
        }
        if fields.contains(.mirror),
           SystemService.setMirror(id, of: saved.mirrorMaster) { done.insert(.mirror) }
        if fields.contains(.origin) {
            let origin = CGPoint(x: saved.originX, y: saved.originY)
            if LayoutService.apply([id: origin]) { done.insert(.origin) }
        }
        return done
    }
}
