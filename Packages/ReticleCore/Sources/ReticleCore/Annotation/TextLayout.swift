import CoreGraphics
import CoreText
import Foundation

/// CoreText measuring and drawing for text and label annotations, so the export
/// matches what the on-screen editor shows.
public enum TextMetrics {
    public static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func attributed(_ text: String, fontSize: CGFloat, color: RGBA) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: fontSize),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
    }

    /// Size of `text` laid out without wrapping. Empty text measures as one line.
    public static func size(of text: String, fontSize: CGFloat) -> CGSize {
        let sample = text.isEmpty ? " " : text
        let setter = CTFramesetterCreateWithAttributedString(attributed(sample, fontSize: fontSize, color: .black))
        let s = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                                                             CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), nil)
        let lineHeight = CTFontGetAscent(font(size: fontSize)) + CTFontGetDescent(font(size: fontSize)) + CTFontGetLeading(font(size: fontSize))
        return CGSize(width: ceil(s.width) + 1, height: max(ceil(s.height), ceil(lineHeight)))
    }

    /// Draws `text` with its top-left at `origin` in a y-down context.
    static func draw(_ text: String, at origin: CGPoint, fontSize: CGFloat, color: RGBA, in ctx: CGContext) {
        guard !text.isEmpty else { return }
        let size = size(of: text, fontSize: fontSize)
        let setter = CTFramesetterCreateWithAttributedString(attributed(text, fontSize: fontSize, color: color))
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: origin.x, y: origin.y + size.height)
        ctx.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}

/// Geometry of a label: a colored anchor dot, a short leader line and a bubble with text.
public struct LabelLayout: Equatable {
    public let dot: CGRect
    public let lineStart: CGPoint
    public let lineEnd: CGPoint
    public let bubble: CGRect
    /// Top-left of the text inside the bubble.
    public let textOrigin: CGPoint

    public init(annotation a: Annotation) {
        self.init(anchor: a.points.first ?? .zero, text: a.text, fontSize: a.style.fontSize, flipped: a.labelFlipped)
    }

    public init(anchor: CGPoint, text: String, fontSize f: CGFloat, flipped: Bool) {
        let r = max(f * 0.35, 4)
        dot = CGRect(x: anchor.x - r, y: anchor.y - r, width: r * 2, height: r * 2)
        let textSize = TextMetrics.size(of: text, fontSize: f)
        let padX = f * 0.5, padY = f * 0.25
        let bubbleSize = CGSize(width: max(textSize.width, f * 2) + padX * 2, height: textSize.height + padY * 2)
        let leader = f * 1.2
        let dir: CGFloat = flipped ? -1 : 1
        lineStart = CGPoint(x: anchor.x + dir * r, y: anchor.y)
        lineEnd = CGPoint(x: anchor.x + dir * (r + leader), y: anchor.y)
        let bubbleX = flipped ? lineEnd.x - bubbleSize.width : lineEnd.x
        bubble = CGRect(x: bubbleX, y: anchor.y - bubbleSize.height / 2, width: bubbleSize.width, height: bubbleSize.height)
        textOrigin = CGPoint(x: bubble.minX + padX, y: bubble.minY + padY)
    }

    public var bounds: CGRect { dot.union(bubble) }
}
