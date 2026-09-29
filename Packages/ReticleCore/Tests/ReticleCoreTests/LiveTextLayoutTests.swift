import CoreGraphics
import XCTest
@testable import ReticleCore

final class LiveTextLayoutTests: XCTestCase {
    /// Two rows: "Hello world" and, below it, "你好世界" next to "OK" on the same row.
    let layout = LiveTextLayout(lines: [
        RecognizedLine(text: "你好世界", box: CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.1)),
        RecognizedLine(text: "Hello world", box: CGRect(x: 0.1, y: 0.1, width: 0.55, height: 0.1)),
        RecognizedLine(text: "OK", box: CGRect(x: 0.6, y: 0.5, width: 0.1, height: 0.1)),
    ])

    func testReadingOrderAndJoining() {
        XCTAssertEqual(layout.count, 11 + 4 + 2)
        XCTAssertEqual(layout.text(in: 0..<layout.count), "Hello world\n你好世界OK")
        XCTAssertEqual(layout.text(in: 6..<13), "world\n你好")
    }

    func testCaretFromPoint() {
        // Equal slices of 0.05 per character on the first line.
        XCTAssertEqual(layout.caret(at: CGPoint(x: 0.1, y: 0.15)), 0)
        XCTAssertEqual(layout.caret(at: CGPoint(x: 0.14, y: 0.15)), 1, "past the middle of H")
        XCTAssertEqual(layout.caret(at: CGPoint(x: 0.9, y: 0.12)), 11, "right of the line: its end")
        XCTAssertEqual(layout.caret(at: CGPoint(x: 0.3, y: 0.53)), 13, "second row, between 好 and 世")
        XCTAssertEqual(layout.caret(at: CGPoint(x: 0.66, y: 0.55)), 16, "inside OK")
    }

    func testHitTesting() {
        XCTAssertTrue(layout.contains(CGPoint(x: 0.3, y: 0.15)))
        XCTAssertFalse(layout.contains(CGPoint(x: 0.3, y: 0.35)), "between rows")
        XCTAssertFalse(layout.contains(CGPoint(x: 0.9, y: 0.9)))
    }

    func testWordAndLine() {
        XCTAssertEqual(layout.text(in: layout.word(at: 2)), "Hello")
        XCTAssertEqual(layout.text(in: layout.word(at: 8)), "world")
        XCTAssertEqual(layout.text(in: layout.line(at: 3)), "Hello world")
        XCTAssertEqual(layout.text(in: layout.line(at: 12)), "你好世界")
    }

    func testDraggingBackwardsSelectsTheSame() {
        XCTAssertEqual(layout.range(from: 9, to: 3), 3..<9)
        XCTAssertEqual(layout.text(in: layout.range(from: 9, to: 3)), "lo wor")
    }

    func testHighlightRectsPerLine() {
        let rects = layout.highlightRects(for: 6..<13)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].minX, 0.1 + 6 * 0.05, accuracy: 1e-6)
        XCTAssertEqual(rects[0].maxX, 0.65, accuracy: 1e-6)
        XCTAssertEqual(rects[1].minX, 0.1, accuracy: 1e-6)
        XCTAssertEqual(rects[1].width, 0.2, accuracy: 1e-6)
        XCTAssertEqual(rects[1].minY, 0.5, accuracy: 1e-6)
        XCTAssertEqual(rects[1].height, 0.1, accuracy: 1e-6)
    }

    func testCharacterBoxesFromVisionAreUsed() {
        let l = LiveTextLayout(lines: [RecognizedLine(text: "ab", box: CGRect(x: 0, y: 0, width: 1, height: 0.1),
                                                      characterBoxes: [CGRect(x: 0, y: 0, width: 0.1, height: 0.1), CGRect(x: 0.8, y: 0, width: 0.2, height: 0.1)])])
        XCTAssertEqual(l.caret(at: CGPoint(x: 0.5, y: 0.05)), 1, "between the real glyphs, not the halves")
    }
}
