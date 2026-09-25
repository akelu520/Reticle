import CoreGraphics
import XCTest
@testable import ReticleCore

final class WindowPickerTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testPicksFrontmostContainingWindow() {
        let windows = [
            CGRect(x: 100, y: 100, width: 200, height: 200), // front
            CGRect(x: 50, y: 50, width: 600, height: 600),   // behind
        ]
        XCTAssertEqual(WindowPicker.pick(at: CGPoint(x: 150, y: 150), windows: windows, screen: screen), windows[0])
        XCTAssertEqual(WindowPicker.pick(at: CGPoint(x: 500, y: 500), windows: windows, screen: screen), windows[1])
    }

    func testFallsBackToScreenAndClipsToScreen() {
        let windows = [CGRect(x: -100, y: -100, width: 300, height: 300)]
        XCTAssertEqual(WindowPicker.pick(at: CGPoint(x: 50, y: 50), windows: windows, screen: screen),
                       CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertEqual(WindowPicker.pick(at: CGPoint(x: 900, y: 700), windows: windows, screen: screen), screen)
    }
}
