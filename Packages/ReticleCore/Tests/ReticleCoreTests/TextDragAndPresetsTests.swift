import CoreGraphics
import XCTest
@testable import ReticleCore

final class TextDragAndPresetsTests: XCTestCase {
    /// A text annotation "hello" at (100, 100), with the text tool still active.
    func modelWithText() -> (EditorModel, UUID) {
        var m = EditorModel(scale: 2)
        m.tool = .text
        _ = m.pointerDown(at: CGPoint(x: 100, y: 100))
        m.finishText("hello")
        return (m, m.document.annotations[0].id)
    }

    func testTextToolDragsExistingText() throws {
        var (m, id) = modelWithText()
        let before = try XCTUnwrap(m.document.annotation(id)).bounds
        let inside = CGPoint(x: before.midX, y: before.midY)
        XCTAssertEqual(m.pointerDown(at: inside), .movingAnnotation)
        m.pointerDragged(to: CGPoint(x: inside.x + 120, y: inside.y + 40))
        XCTAssertEqual(m.pointerUp(), .none, "a drag does not start editing")
        let after = try XCTUnwrap(m.document.annotation(id)).bounds
        XCTAssertEqual(after.minX - before.minX, 120, accuracy: 0.001)
        XCTAssertEqual(after.minY - before.minY, 40, accuracy: 0.001)
        XCTAssertEqual(m.document.annotations.count, 1, "no new text was created")
        XCTAssertEqual(m.tool, .text, "the text tool stays active")
        m.undo()
        XCTAssertEqual(try XCTUnwrap(m.document.annotation(id)).bounds, before, "the move is one undo step")
    }

    func testTextToolClickWithoutDragEdits() throws {
        var (m, id) = modelWithText()
        let b = try XCTUnwrap(m.document.annotation(id)).bounds
        _ = m.pointerDown(at: CGPoint(x: b.midX, y: b.midY))
        // Jitter below the drag threshold (2 pt at scale 2 = 4 px).
        m.pointerDragged(to: CGPoint(x: b.midX + 3, y: b.midY + 1))
        XCTAssertEqual(m.pointerUp(), .editText(id))
        XCTAssertEqual(try XCTUnwrap(m.document.annotation(id)).bounds, b, "jitter does not move the text")
    }

    func testTextToolOnEmptySpaceStillCreatesText() {
        var (m, _) = modelWithText()
        XCTAssertEqual(m.pointerDown(at: CGPoint(x: 600, y: 600)), .beginText(origin: CGPoint(x: 600, y: 600)))
    }

    func testPresetsRoundTrip() {
        var m = EditorModel(scale: 2)
        m.tool = .text
        m.setFontSize(20)
        m.setTextStyle(.outline)
        m.setColor(.blue)
        m.tool = .rect
        m.setSize(.large)
        let data = EditorModel.encodePresets(m.toolPresets)
        let restored = EditorModel(scale: 1, presets: EditorModel.decodePresets(data))
        XCTAssertEqual(restored.preset(for: .text).fontSize, 20)
        XCTAssertEqual(restored.preset(for: .text).textStyle, .outline)
        XCTAssertEqual(restored.preset(for: .text).color, .blue)
        XCTAssertEqual(restored.preset(for: .rect).size, .large)
        XCTAssertEqual(restored.preset(for: .arrow), ToolPreset(color: .red, size: .small), "untouched tools keep defaults")
    }

    func testBrokenSavedPresetsFallBackToDefaults() {
        XCTAssertTrue(EditorModel.decodePresets(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(EditorModel.decodePresets(nil).isEmpty)
        // An unknown tool and an unsupported font size are ignored.
        var odd = ToolPreset(color: .red, size: .small)
        odd.fontSize = 13
        let data = try! JSONEncoder().encode(["text": odd, "sticker": ToolPreset(color: .red, size: .small)])
        XCTAssertTrue(EditorModel.decodePresets(data).isEmpty)
    }
}
