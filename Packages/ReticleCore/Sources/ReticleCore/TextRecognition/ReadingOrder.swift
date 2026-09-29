import CoreGraphics
import Foundation

/// One line of recognized text. `box` is normalized (0...1) with a top-left origin.
public struct RecognizedLine: Equatable, Sendable, Codable {
    public var text: String
    public var box: CGRect
    /// One box per character of `text`, normalized like `box`; empty when unknown.
    public var characterBoxes: [CGRect]

    public init(text: String, box: CGRect, characterBoxes: [CGRect] = []) {
        self.text = text
        self.box = box
        self.characterBoxes = characterBoxes
    }
}

/// Turns loose OCR lines into readable text: rows top to bottom, left to right within a row.
public enum ReadingOrder {
    public static func text(from lines: [RecognizedLine]) -> String {
        rows(from: lines).map { row in
            row.map(\.text).reduce("") { joined, next in joined + separator(joining: joined, next) + next }
        }.joined(separator: "\n")
    }

    /// Lines grouped into rows, top to bottom, each row left to right.
    public static func rows(from lines: [RecognizedLine]) -> [[RecognizedLine]] {
        var rows: [[RecognizedLine]] = []
        for line in lines.sorted(by: { $0.box.minY < $1.box.minY }) {
            // Same row when the line's vertical center falls inside the row's first line.
            if let first = rows.last?.first, line.box.midY >= first.box.minY, line.box.midY <= first.box.maxY {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// What goes between two pieces of text on one row: nothing next to CJK, otherwise a space.
    static func separator(joining a: String, _ b: String) -> String {
        guard let last = a.last, let first = b.first else { return "" }
        return last.isCJK || first.isCJK ? "" : " "
    }
}

extension Character {
    /// Han, Kana, Hangul and CJK punctuation — joined without spaces.
    var isCJK: Bool {
        unicodeScalars.contains { s in
            switch s.value {
            case 0x3000...0x303F, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
                return true
            default:
                return false
            }
        }
    }
}
