import Foundation
import CoreGraphics

enum RotationPolicy {
    static let angles = [0, 90, 180, 270]

    static func next(current: Int, step: Int) -> Int {
        let base = normalize(current)
        let index = (angles.firstIndex(of: base) ?? 0) + step
        let count = angles.count
        return angles[((index % count) + count) % count]
    }

    static func normalize(_ degrees: Int) -> Int {
        var d = degrees % 360
        if d < 0 { d += 360 }
        let snapped = Int((Double(d) / 90).rounded()) * 90
        return snapped % 360
    }
}

enum RotationService {
    static func current(_ id: CGDirectDisplayID) -> Int {
        RotationPolicy.normalize(Int(CGDisplayRotation(id).rounded()))
    }

    static func canRotate(_ id: CGDirectDisplayID) -> Bool {
        guard let mp = PresetService.display(for: id) else { return false }
        return (mp.value(forKey: "canChangeOrientation") as? Bool) ?? false
    }

    static var ready: Bool { PresetService.manager() != nil }

    @discardableResult
    static func set(_ id: CGDirectDisplayID, degrees: Int) -> Bool {
        guard canRotate(id), let mp = PresetService.display(for: id) else { return false }
        let sel = NSSelectorFromString("setOrientation:")
        guard mp.responds(to: sel), let imp = mp.method(for: sel) else { return false }
        let target = Int32(RotationPolicy.normalize(degrees))
        PresetService.withLock {
            typealias SetOrientation = @convention(c) (AnyObject, Selector, Int32) -> Void
            unsafeBitCast(imp, to: SetOrientation.self)(mp, sel, target)
        }
        return true
    }
}
