import XCTest
import CoreGraphics
@testable import MonitorPilot

final class LayoutPlannerTests: XCTestCase {
    private let anchor = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let moving = CGRect(x: 5000, y: 300, width: 1280, height: 800)

    func testSides() {
        XCTAssertEqual(LayoutPlanner.origin(for: moving, relativeTo: anchor, side: .left),
                       CGPoint(x: -1280, y: 0))
        XCTAssertEqual(LayoutPlanner.origin(for: moving, relativeTo: anchor, side: .right),
                       CGPoint(x: 1920, y: 0))
        XCTAssertEqual(LayoutPlanner.origin(for: moving, relativeTo: anchor, side: .above),
                       CGPoint(x: 0, y: -800))
        XCTAssertEqual(LayoutPlanner.origin(for: moving, relativeTo: anchor, side: .below),
                       CGPoint(x: 0, y: 1080))
    }

    func testEdgesTouch() {
        let left = LayoutPlanner.origin(for: moving, relativeTo: anchor, side: .left)
        XCTAssertEqual(left.x + moving.width, anchor.minX)
        let below = LayoutPlanner.origin(for: moving, relativeTo: anchor, side: .below)
        XCTAssertEqual(below.y, anchor.maxY)
    }

    func testNormalizedKeepsMainAtZero() {
        let frames: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 100, y: 50, width: 1920, height: 1080),
            2: CGRect(x: 2020, y: 50, width: 1280, height: 800),
        ]
        let origins = LayoutPlanner.normalized(frames, main: 1)
        XCTAssertEqual(origins[1], .zero)
        XCTAssertEqual(origins[2], CGPoint(x: 1920, y: 0))
    }

    func testNormalizedWhenMainItselfMoved() {
        let frames: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: -1280, y: 0, width: 1280, height: 800),
            2: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ]
        let origins = LayoutPlanner.normalized(frames, main: 1)
        XCTAssertEqual(origins[1], .zero)
        XCTAssertEqual(origins[2], CGPoint(x: 1280, y: 0))
    }
}
