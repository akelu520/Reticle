import CoreGraphics
import XCTest
@testable import ReticleCore

final class EditorModelTests: XCTestCase {
    func drawRect(_ m: inout EditorModel, from a: CGPoint, to b: CGPoint) {
        XCTAssertEqual(m.pointerDown(at: a), .drawing)
        m.pointerDragged(to: b)
        m.pointerUp()
    }

    func testDrawRectAddsAnnotationWithScaledStyle() {
        var m = EditorModel(scale: 2)
        m.tool = .rect
        drawRect(&m, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 60))
        XCTAssertEqual(m.document.annotations.count, 1)
        let a = m.document.annotations[0]
        XCTAssertEqual(a.kind, .rect)
        XCTAssertEqual(a.spanRect, CGRect(x: 10, y: 10, width: 100, height: 50))
        XCTAssertEqual(a.style.lineWidth, 8) // medium 4pt × 2
        XCTAssertEqual(a.style.color, .red)
    }

    func testClickWithoutDragAddsNothing() {
        var m = EditorModel(scale: 1)
        m.tool = .ellipse
        drawRect(&m, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 11))
        XCTAssertTrue(m.document.annotations.isEmpty)
        XCTAssertFalse(m.canUndo)
    }

    func testShiftConstrainsToSquareAnd45Degrees() {
        XCTAssertEqual(EditorModel.constrained(from: .zero, to: CGPoint(x: 30, y: -10), kind: .rect), CGPoint(x: 30, y: -30))
        let p = EditorModel.constrained(from: .zero, to: CGPoint(x: 100, y: 10), kind: .arrow)
        XCTAssertEqual(p.y, 0, accuracy: 0.001)
        XCTAssertEqual(p.x, hypot(100, 10), accuracy: 0.001)
    }

    func testPenSamplesPointsAndSingleClickMakesDot() {
        var m = EditorModel(scale: 1)
        m.tool = .pen
        _ = m.pointerDown(at: CGPoint(x: 0, y: 0))
        m.pointerDragged(to: CGPoint(x: 0.2, y: 0)) // below sampling distance
        m.pointerDragged(to: CGPoint(x: 5, y: 0))
        m.pointerDragged(to: CGPoint(x: 10, y: 5))
        m.pointerUp()
        XCTAssertEqual(m.document.annotations[0].points.count, 3)

        _ = m.pointerDown(at: CGPoint(x: 50, y: 50))
        m.pointerUp()
        XCTAssertEqual(m.document.annotations[1].points, [CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 50)])
    }

    func testUndoRedo() {
        var m = EditorModel(scale: 1)
        m.tool = .rect
        drawRect(&m, from: .zero, to: CGPoint(x: 20, y: 20))
        drawRect(&m, from: CGPoint(x: 30, y: 30), to: CGPoint(x: 60, y: 60))
        m.undo()
        XCTAssertEqual(m.document.annotations.count, 1)
        m.undo()
        XCTAssertEqual(m.document.annotations.count, 0)
        XCTAssertFalse(m.canUndo)
        m.redo()
        XCTAssertEqual(m.document.annotations.count, 1)
        drawRect(&m, from: CGPoint(x: 70, y: 70), to: CGPoint(x: 90, y: 90))
        XCTAssertFalse(m.canRedo, "a new change clears redo")
    }

    func testSelectMoveAndDeleteWithoutTool() {
        var m = EditorModel(scale: 1)
        m.tool = .rect
        drawRect(&m, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50))
        m.tool = nil
        XCTAssertEqual(m.pointerDown(at: CGPoint(x: 30, y: 30)), .none, "inside an outline-only rect is empty space")
        XCTAssertEqual(m.pointerDown(at: CGPoint(x: 10, y: 30)), .movingAnnotation)
        m.pointerDragged(to: CGPoint(x: 20, y: 40))
        m.pointerUp()
        XCTAssertEqual(m.document.annotations[0].spanRect.origin, CGPoint(x: 20, y: 20))
        m.undo()
        XCTAssertEqual(m.document.annotations[0].spanRect.origin, CGPoint(x: 10, y: 10))
        _ = m.pointerDown(at: CGPoint(x: 10, y: 30))
        m.pointerUp()
        XCTAssertTrue(m.deleteSelected())
        XCTAssertTrue(m.document.annotations.isEmpty)
    }

    func testStyleChangeAppliesToSelectionAndIsUndoable() {
        var m = EditorModel(scale: 1)
        m.tool = .arrow
        _ = m.pointerDown(at: CGPoint(x: 0, y: 0))
        m.pointerDragged(to: CGPoint(x: 100, y: 0))
        m.pointerUp()
        m.tool = nil
        _ = m.pointerDown(at: CGPoint(x: 50, y: 0))
        m.pointerUp()
        XCTAssertEqual(m.styleTarget, .arrow)
        m.setColor(.blue)
        m.setSize(.large)
        XCTAssertEqual(m.document.annotations[0].style.color, .blue)
        XCTAssertEqual(m.document.annotations[0].style.lineWidth, 8)
        XCTAssertEqual(m.currentPreset, ToolPreset(color: .blue, size: .large))
        m.undo()
        XCTAssertEqual(m.document.annotations[0].style.lineWidth, 4)
        XCTAssertEqual(m.preset(for: .arrow).color, .blue, "the tool remembers the last color")
    }

    func testTextCreateEditAndEmptyDeletes() {
        var m = EditorModel(scale: 2)
        m.tool = .text
        XCTAssertEqual(m.pointerDown(at: CGPoint(x: 5, y: 5)), .beginText(origin: CGPoint(x: 5, y: 5)))
        XCTAssertEqual(m.pendingTextStyle?.fontSize, 36) // medium 18pt × 2
        m.finishText("hello")
        XCTAssertEqual(m.document.annotations.first?.text, "hello")

        let id = m.document.annotations[0].id
        XCTAssertEqual(m.pointerDown(at: CGPoint(x: 10, y: 10)), .editText(id))
        XCTAssertEqual(m.visibleAnnotations.count, 0, "hidden while editing")
        m.finishText("   ")
        XCTAssertTrue(m.document.annotations.isEmpty)

        m.tool = .text
        _ = m.pointerDown(at: CGPoint(x: 5, y: 5))
        m.finishText("")
        XCTAssertTrue(m.document.annotations.isEmpty, "empty new text is discarded")
    }

    func testLabelCreateAndFlipByClickingDot() {
        var m = EditorModel(scale: 1)
        m.tool = .label
        XCTAssertEqual(m.pointerDown(at: CGPoint(x: 100, y: 100)), .beginLabel(anchor: CGPoint(x: 100, y: 100)))
        m.finishText("说明")
        XCTAssertEqual(m.document.annotations[0].labelFlipped, false)
        XCTAssertEqual(m.pointerDown(at: CGPoint(x: 101, y: 100)), .flippedLabel)
        XCTAssertEqual(m.document.annotations[0].labelFlipped, true)
        XCTAssertLessThan(LabelLayout(annotation: m.document.annotations[0]).bubble.maxX, 100)
        m.undo()
        XCTAssertEqual(m.document.annotations[0].labelFlipped, false)
    }

    func testDoubleClickEditsTextEvenWithShapeTool() {
        var m = EditorModel(scale: 1)
        m.tool = .text
        _ = m.pointerDown(at: CGPoint(x: 5, y: 5))
        m.finishText("abc")
        m.tool = .rect
        let id = m.document.annotations[0].id
        XCTAssertEqual(m.pointerDown(at: CGPoint(x: 8, y: 8), clickCount: 2), .editText(id))
    }

    func testMosaicModeChoosesKind() {
        var m = EditorModel(scale: 1)
        m.tool = .mosaic
        m.mosaicMode = .box
        drawRect(&m, from: .zero, to: CGPoint(x: 40, y: 40))
        XCTAssertEqual(m.document.annotations[0].kind, .mosaicBox)
        m.mosaicMode = .brush
        _ = m.pointerDown(at: CGPoint(x: 50, y: 50))
        m.pointerUp()
        XCTAssertEqual(m.document.annotations[1].kind, .mosaicBrush)
        XCTAssertEqual(m.document.annotations[1].style.lineWidth, 20)
    }

    func testWatermarkSetClearAndUndo() {
        var m = EditorModel(scale: 1)
        m.setWatermark(Watermark(text: "机密", opacity: 0.3, color: .black, fontSize: 18))
        XCTAssertEqual(m.document.watermark?.text, "机密")
        m.setWatermark(Watermark(text: "", opacity: 0.3, color: .black, fontSize: 18))
        XCTAssertNil(m.document.watermark)
        m.undo()
        XCTAssertEqual(m.document.watermark?.text, "机密")
    }

    func testHistoryLimit() {
        var h = History<Int>(limit: 3)
        for i in 0..<5 { h.record(i) }
        var current = 5
        var restored: [Int] = []
        while let prev = h.undo(from: current) { restored.append(prev); current = prev }
        XCTAssertEqual(restored, [4, 3, 2])
    }
}
