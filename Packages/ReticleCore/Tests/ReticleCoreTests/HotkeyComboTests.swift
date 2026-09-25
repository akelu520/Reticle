import XCTest
@testable import ReticleCore

final class HotkeyComboTests: XCTestCase {
    func testDefaultHotkeys() {
        XCTAssertEqual(HotkeyCombo.defaultCapture.displayString, "⇧⌘A")
        XCTAssertEqual(HotkeyCombo.defaultRecord.displayString, "⌥⇧R")
    }

    func testCarbonModifierMapping() {
        let combo = HotkeyCombo(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(combo.carbonModifiers, 256 | 512 | 2048 | 4096)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(HotkeyCombo.defaultCapture)
        XCTAssertEqual(try JSONDecoder().decode(HotkeyCombo.self, from: data), .defaultCapture)
    }

    func testRequiresModifier() {
        XCTAssertFalse(HotkeyCombo(keyCode: 0, modifiers: []).isValid)
        XCTAssertFalse(HotkeyCombo(keyCode: 0, modifiers: [.shift]).isValid)
        XCTAssertTrue(HotkeyCombo(keyCode: 0, modifiers: [.command]).isValid)
    }
}
