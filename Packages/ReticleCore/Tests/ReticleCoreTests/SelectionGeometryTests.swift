import CoreGraphics
import XCTest
@testable import ReticleCore

final class SelectionGeometryTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testRectFromDragNormalizesAndClamps() {
        let r = SelectionGeometry.rect(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: -50), within: bounds)
        XCTAssertEqual(r, CGRect(x: 100, y: 0, width: 200, height: 200))
    }

    func testHandleHitTestFindsCornerAndEdge() {
        let sel = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 101, y: 99), in: sel), .topLeft)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 200, y: 200), in: sel), .bottom)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 302, y: 150), in: sel), .right)
        XCTAssertNil(SelectionGeometry.handle(at: CGPoint(x: 200, y: 150), in: sel))
    }

    func testResizeFromCornerCanFlip() {
        let sel = CGRect(x: 100, y: 100, width: 200, height: 100)
        let r = SelectionGeometry.resize(sel, handle: .bottomRight, to: CGPoint(x: 50, y: 60), within: bounds)
        XCTAssertEqual(r, CGRect(x: 50, y: 60, width: 50, height: 40))
    }

    func testResizeEdgeOnlyChangesOneAxis() {
        let sel = CGRect(x: 100, y: 100, width: 200, height: 100)
        let r = SelectionGeometry.resize(sel, handle: .top, to: CGPoint(x: 999, y: 20), within: bounds)
        XCTAssertEqual(r, CGRect(x: 100, y: 20, width: 200, height: 180))
    }

    func testMoveStaysInsideBounds() {
        let sel = CGRect(x: 900, y: 700, width: 80, height: 80)
        let r = SelectionGeometry.move(sel, by: CGVector(dx: 50, dy: 50), within: bounds)
        XCTAssertEqual(r, CGRect(x: 920, y: 720, width: 80, height: 80))
        let l = SelectionGeometry.move(sel, by: CGVector(dx: -2000, dy: 0), within: bounds)
        XCTAssertEqual(l.minX, 0)
    }

    func testToolbarPlacementPrefersBelowThenAboveThenInside() {
        let size = CGSize(width: 300, height: 40)
        let below = SelectionGeometry.toolbarOrigin(for: CGRect(x: 100, y: 100, width: 400, height: 200), toolbar: size, within: bounds)
        XCTAssertEqual(below, CGPoint(x: 200, y: 308))
        let above = SelectionGeometry.toolbarOrigin(for: CGRect(x: 100, y: 500, width: 400, height: 280), toolbar: size, within: bounds)
        XCTAssertEqual(above, CGPoint(x: 200, y: 452))
        let inside = SelectionGeometry.toolbarOrigin(for: bounds, toolbar: size, within: bounds)
        XCTAssertEqual(inside, CGPoint(x: 692, y: 752))
    }
}
