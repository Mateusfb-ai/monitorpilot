import Foundation
import CoreGraphics

enum LayoutPlanner {
    enum Side: String, CaseIterable {
        case left, right, above, below

        var label: String {
            switch self {
            case .left: return "à esquerda de"
            case .right: return "à direita de"
            case .above: return "acima de"
            case .below: return "abaixo de"
            }
        }
    }

    static func origin(for moving: CGRect, relativeTo anchor: CGRect, side: Side) -> CGPoint {
        switch side {
        case .left:  return CGPoint(x: anchor.minX - moving.width, y: anchor.minY)
        case .right: return CGPoint(x: anchor.maxX, y: anchor.minY)
        case .above: return CGPoint(x: anchor.minX, y: anchor.minY - moving.height)
        case .below: return CGPoint(x: anchor.minX, y: anchor.maxY)
        }
    }

    static func normalized(_ frames: [CGDirectDisplayID: CGRect], main: CGDirectDisplayID)
        -> [CGDirectDisplayID: CGPoint]
    {
        let offset = frames[main]?.origin ?? .zero
        return frames.mapValues {
            CGPoint(x: $0.origin.x - offset.x, y: $0.origin.y - offset.y)
        }
    }
}

enum LayoutService {
    @discardableResult
    static func move(_ display: CGDirectDisplayID, relativeTo anchor: CGDirectDisplayID,
                     side: LayoutPlanner.Side) -> Bool
    {
        guard display != anchor else { return false }
        let all = DisplayManager.onlineDisplays()
        guard let main = all.first(where: \.isMain)?.id ?? all.first?.id else { return false }
        var frames = Dictionary(uniqueKeysWithValues: all.map { ($0.id, CGDisplayBounds($0.id)) })
        guard let moving = frames[display], let target = frames[anchor] else { return false }
        var newFrame = moving
        newFrame.origin = LayoutPlanner.origin(for: moving, relativeTo: target, side: side)
        frames[display] = newFrame
        let origins = LayoutPlanner.normalized(frames, main: main)
        return apply(origins)
    }

    @discardableResult
    static func apply(_ origins: [CGDirectDisplayID: CGPoint]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for (id, origin) in origins {
            guard CGConfigureDisplayOrigin(
                config, id, Int32(origin.x.rounded()), Int32(origin.y.rounded())) == .success
            else {
                CGCancelDisplayConfiguration(config)
                return false
            }
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
