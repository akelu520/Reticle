import CoreGraphics
import Foundation

/// Recognized text laid out for selecting it in place, like Live Text.
///
/// Characters are numbered in reading order (rows top to bottom, left to right); a selection
/// is a range of caret positions `0...count` between them. Coordinates are normalized to the
/// recognized image (0...1, top-left origin).
public struct LiveTextLayout: Sendable {
    struct Glyph: Sendable {
        var character: Character
        var rect: CGRect
        var line: Int
    }

    struct Line: Sendable {
        var box: CGRect
        var glyphs: Range<Int>
        /// Inserted before the line's first character when a selection spans into it.
        var separator: String
    }

    let glyphs: [Glyph]
    let lines: [Line]

    public var isEmpty: Bool { glyphs.isEmpty }
    public var count: Int { glyphs.count }

    public init(lines recognized: [RecognizedLine]) {
        var glyphs: [Glyph] = []
        var lines: [Line] = []
        for (r, row) in ReadingOrder.rows(from: recognized).enumerated() {
            var rowText = ""
            for (k, line) in row.enumerated() where !line.text.isEmpty {
                let characters = Array(line.text)
                let boxes = line.characterBoxes.count == characters.count ? line.characterBoxes : Self.split(line.box, into: characters.count)
                let start = glyphs.count
                for (c, box) in zip(characters, boxes) {
                    glyphs.append(Glyph(character: c, rect: box, line: lines.count))
                }
                let separator = k == 0 ? (r == 0 ? "" : "\n") : ReadingOrder.separator(joining: rowText, line.text)
                lines.append(Line(box: line.box, glyphs: start..<glyphs.count, separator: separator))
                rowText += line.text
            }
        }
        self.glyphs = glyphs
        self.lines = lines
    }

    /// Equal slices of `box`, when Vision gives no per-character boxes.
    static func split(_ box: CGRect, into n: Int) -> [CGRect] {
        guard n > 0 else { return [] }
        let w = box.width / CGFloat(n)
        return (0..<n).map { CGRect(x: box.minX + CGFloat($0) * w, y: box.minY, width: w, height: box.height) }
    }

    /// Whether `p` is over text, with a little slack around each line.
    public func contains(_ p: CGPoint) -> Bool {
        lines.contains { $0.box.insetBy(dx: -$0.box.height * 0.2, dy: -$0.box.height * 0.2).contains(p) }
    }

    /// Caret position closest to `p`: the nearest line, then the gap nearest in x.
    public func caret(at p: CGPoint) -> Int {
        guard let line = lines.min(by: { distance(p, $0.box) < distance(p, $1.box) }) else { return 0 }
        for i in line.glyphs where p.x < glyphs[i].rect.midX { return i }
        return line.glyphs.upperBound
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        // Rows matter more than columns: stay on the row the pointer is on.
        return hypot(dx, dy * 4)
    }

    /// The selection between two carets.
    public func range(from a: Int, to b: Int) -> Range<Int> {
        min(a, b)..<max(a, b)
    }

    /// The word containing the character at or after caret `i` (a single character when not in a word).
    public func word(at i: Int) -> Range<Int> {
        guard !glyphs.isEmpty else { return 0..<0 }
        let g = min(i, glyphs.count - 1)
        let line = lines[glyphs[g].line]
        let text = String(glyphs[line.glyphs].map(\.character))
        let offset = g - line.glyphs.lowerBound
        var result = g..<(g + 1)
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, range, _, stop in
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            if offset >= lower, offset < upper {
                result = (line.glyphs.lowerBound + lower)..<(line.glyphs.lowerBound + upper)
                stop = true
            }
        }
        return result
    }

    /// The whole line containing the character at or after caret `i`.
    public func line(at i: Int) -> Range<Int> {
        guard !glyphs.isEmpty else { return 0..<0 }
        return lines[glyphs[min(i, glyphs.count - 1)].line].glyphs
    }

    /// The selected text, with spaces and line breaks where lines join.
    public func text(in range: Range<Int>) -> String {
        var out = ""
        for i in range.clamped(to: 0..<glyphs.count) {
            let line = lines[glyphs[i].line]
            if i == line.glyphs.lowerBound, i != range.lowerBound { out += line.separator }
            out.append(glyphs[i].character)
        }
        return out
    }

    /// One highlight rectangle per line touched by `range`, as tall as the line.
    public func highlightRects(for range: Range<Int>) -> [CGRect] {
        lines.compactMap { line in
            let part = line.glyphs.clamped(to: range)
            guard !part.isEmpty else { return nil }
            let minX = glyphs[part.lowerBound].rect.minX, maxX = glyphs[part.upperBound - 1].rect.maxX
            return CGRect(x: minX, y: line.box.minY, width: maxX - minX, height: line.box.height)
        }
    }
}
