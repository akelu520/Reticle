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

/// Geometry of a label: a colored anchor dot and, a small gap away, a dark bubble
/// whose notch points back at the dot.
public struct LabelLayout: Equatable {
    public let dot: CGRect
    public let bubble: CGRect
    /// Tip of the notch, on the dot side.
    public let notchTip: CGPoint
    public let flipped: Bool
    /// Top-left of the text inside the bubble.
    public let textOrigin: CGPoint

    public init(annotation a: Annotation) {
        self.init(anchor: a.points.first ?? .zero, text: a.text, fontSize: a.style.fontSize, flipped: a.labelFlipped)
    }

    public init(anchor: CGPoint, text: String, fontSize f: CGFloat, flipped: Bool) {
        let r = max(f * 0.3, 3)
        dot = CGRect(x: anchor.x - r, y: anchor.y - r, width: r * 2, height: r * 2)
        let textSize = TextMetrics.size(of: text, fontSize: f)
        let padX = f * 0.7, padY = f * 0.75
        let bubbleSize = CGSize(width: max(textSize.width, f * 2.2) + padX * 2, height: textSize.height + padY * 2)
        let dir: CGFloat = flipped ? -1 : 1
        let notch = f * 0.45
        notchTip = CGPoint(x: anchor.x + dir * (r + f * 0.3), y: anchor.y)
        let edge = notchTip.x + dir * notch
        let bubbleX = flipped ? edge - bubbleSize.width : edge
        bubble = CGRect(x: bubbleX, y: anchor.y - bubbleSize.height / 2, width: bubbleSize.width, height: bubbleSize.height)
        textOrigin = CGPoint(x: bubble.minX + padX, y: bubble.minY + padY)
        self.flipped = flipped
    }

    public var bounds: CGRect { dot.union(bubble).union(CGRect(origin: notchTip, size: .zero)) }

    /// Rounded bubble plus the triangular notch toward the dot.
    public var bubblePath: CGPath {
        let path = CGMutablePath()
        let radius = min(bubble.height * 0.3, bubble.width / 2)
        path.addRoundedRect(in: bubble, cornerWidth: radius, cornerHeight: radius)
        let edgeX = flipped ? bubble.maxX : bubble.minX
        let half = min(bubble.height * 0.22, bubble.height / 2 - radius)
        path.addLines(between: [CGPoint(x: edgeX, y: notchTip.y - half), notchTip, CGPoint(x: edgeX, y: notchTip.y + half)])
        path.closeSubpath()
        return path
    }
}
