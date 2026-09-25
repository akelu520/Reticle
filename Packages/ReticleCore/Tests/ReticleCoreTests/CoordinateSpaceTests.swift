import CoreGraphics
import XCTest
@testable import ReticleCore

final class CoordinateSpaceTests: XCTestCase {
    func testCGGlobalToLocalOnPrimaryScreen() {
        // Primary screen 1440x900, AppKit frame origin (0,0).
        let local = CoordinateSpace.localFlipped(fromCGGlobal: CGRect(x: 10, y: 20, width: 100, height: 50),
                                                 screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                                 primaryHeight: 900)
        XCTAssertEqual(local, CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    func testCGGlobalToLocalOnSecondaryScreenAbove() {
        // Secondary screen sits above primary: AppKit frame (0, 900, 1920, 1080).
        // In CG global coords its top-left is (0, -1080).
        let local = CoordinateSpace.localFlipped(fromCGGlobal: CGRect(x: 30, y: -1000, width: 100, height: 100),
                                                 screenFrame: CGRect(x: 0, y: 900, width: 1920, height: 1080),
                                                 primaryHeight: 900)
        XCTAssertEqual(local, CGRect(x: 30, y: 80, width: 100, height: 100))
    }

    func testPixelRectScalesAndRoundsOutward() {
        let px = CoordinateSpace.pixelRect(fromPoints: CGRect(x: 10.3, y: 5.6, width: 20, height: 10), scale: 2)
        XCTAssertEqual(px, CGRect(x: 20, y: 11, width: 41, height: 21))
    }

    func testPixelRectIgnoresFloatingPointNoise() {
        // 151.2 + 604.8 is 756.0000000000001 in Double; must still give 1210 px, not 1211.
        let r = CGRect(x: 151.2, y: 98.2, width: 604.8, height: 491.00000000000006)
        let px = CoordinateSpace.pixelRect(fromPoints: r, scale: 2)
        XCTAssertEqual(px.width, 1210)
        XCTAssertEqual(px.height, 983)
    }
}

final class AppKitGlobalTests: XCTestCase {
    func testLocalFlippedToAppKitGlobal() {
        // Secondary screen at AppKit (1440, 0, 1920, 1080); a rect 100pt from its top.
        let r = CoordinateSpace.appKitGlobal(fromLocalFlipped: CGRect(x: 10, y: 100, width: 200, height: 50),
                                             screenFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(r, CGRect(x: 1450, y: 930, width: 200, height: 50))
    }
}
