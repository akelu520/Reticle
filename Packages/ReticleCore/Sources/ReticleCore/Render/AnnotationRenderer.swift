import CoreGraphics
import Foundation

/// Draws annotations and the watermark. Every function expects a context in
/// image-pixel space with a top-left origin (y down). The on-screen canvas and
/// the exporter both call into here, so what you see is what you get.
public enum AnnotationRenderer {
    /// - Parameters:
    ///   - pixelated: mosaic source covering the whole base image, or nil to fall back to gray.
    ///   - baseSize: size of the base image in pixels.
    public static func draw(_ annotations: [Annotation], pixelated: CGImage?, baseSize: CGSize, in ctx: CGContext) {
        for a in Document.paintOrder(annotations) {
            draw(a, pixelated: pixelated, baseSize: baseSize, in: ctx)
        }
    }

    static func draw(_ a: Annotation, pixelated: CGImage?, baseSize: CGSize, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let s = a.style
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch a.kind {
        case .rect:
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(s.lineWidth)
            ctx.addPath(ShapePaths.roundedRect(a.spanRect, lineWidth: s.lineWidth))
            ctx.strokePath()
        case .line:
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(s.lineWidth)
            ctx.move(to: a.points.first ?? .zero)
            ctx.addLine(to: a.points.last ?? .zero)
            ctx.strokePath()
        case .ellipse:
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(s.lineWidth)
            ctx.strokeEllipse(in: a.spanRect)
        case .arrow:
            ctx.setFillColor(s.color.cgColor)
            ctx.addPath(ShapePaths.arrow(from: a.points.first ?? .zero, to: a.points.last ?? .zero, width: s.lineWidth))
            ctx.fillPath()
        case .pen:
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(s.lineWidth)
            ctx.addPath(ShapePaths.stroke(a.points))
            ctx.strokePath()
        case .highlight:
            ctx.setStrokeColor(s.color.withAlpha(0.4).cgColor)
            ctx.setLineWidth(s.lineWidth)
            ctx.addPath(ShapePaths.stroke(a.points))
            ctx.strokePath()
        case .mosaicBrush, .mosaicBox:
            if a.kind == .mosaicBox {
                ctx.clip(to: a.spanRect)
            } else {
                ctx.setLineWidth(s.lineWidth)
                ctx.addPath(ShapePaths.stroke(a.points))
                ctx.replacePathWithStrokedPath()
                ctx.clip()
            }
            let full = CGRect(origin: .zero, size: baseSize)
            if let pixelated {
                drawImage(pixelated, in: full, ctx: ctx)
            } else {
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
                ctx.fill(full)
            }
        case .text:
            TextMetrics.draw(a.text, at: a.points.first ?? .zero, fontSize: s.fontSize, color: s.color, in: ctx)
        case .label:
            drawLabel(a, in: ctx)
        }
    }

    /// Colored anchor dot, then a dark slate bubble with a notch pointing at it and white text.
    /// `drawText: false` draws only the dot and bubble (the editor overlays a live text field).
    public static func drawLabel(_ a: Annotation, drawText: Bool = true, in ctx: CGContext) {
        let l = LabelLayout(annotation: a)
        ctx.setFillColor(RGBA.slate.cgColor)
        ctx.addPath(l.bubblePath)
        ctx.fillPath()

        // Dot with a soft white ring so it stays visible on any background.
        ctx.setFillColor(RGBA.white.withAlpha(0.9).cgColor)
        ctx.fillEllipse(in: l.dot.insetBy(dx: -l.dot.width * 0.15, dy: -l.dot.height * 0.15))
        ctx.setFillColor(a.style.color.cgColor)
        ctx.fillEllipse(in: l.dot)

        if drawText {
            TextMetrics.draw(a.text, at: l.textOrigin, fontSize: a.style.fontSize, color: .white, in: ctx)
        }
    }

    /// Tiles the watermark text across `area`, rotated −30°.
    public static func drawWatermark(_ w: Watermark, in area: CGRect, ctx: CGContext) {
        guard !w.text.isEmpty, area.width > 0, area.height > 0 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: area)
        ctx.setAlpha(w.opacity)
        let size = TextMetrics.size(of: w.text, fontSize: w.fontSize)
        let stepX = size.width + w.fontSize * 4
        let stepY = size.height + w.fontSize * 4
        ctx.translateBy(x: area.midX, y: area.midY)
        ctx.rotate(by: -.pi / 6)
        let reach = hypot(area.width, area.height) / 2 + max(stepX, stepY)
        var row = 0
        var y = -reach
        while y <= reach {
            // Offset every other row by half a step for a staggered pattern.
            var x = -reach + (row % 2 == 0 ? 0 : stepX / 2)
            while x <= reach {
                TextMetrics.draw(w.text, at: CGPoint(x: x, y: y), fontSize: w.fontSize, color: w.color, in: ctx)
                x += stepX
            }
            y += stepY
            row += 1
        }
    }

    /// Draws a CGImage upright in a y-down context.
    public static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }
}
