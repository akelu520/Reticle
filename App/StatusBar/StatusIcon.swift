import AppKit

/// Menu-bar version of the app icon (design/AppIcon.svg): the two overlapping
/// L-shaped strokes, monochrome, drawn as a template image so the system tints
/// it for light and dark menu bars.
enum StatusIcon {
    static func make() -> NSImage {
        let size = CGSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            // SVG artwork spans 182…842 (strokes 124 wide, round caps) in a 1024 canvas.
            let scale = rect.width / 660
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 182) * scale, y: (y - 182) * scale) }
            for points in [[p(366, 244), p(366, 658), p(780, 658)], [p(244, 366), p(658, 366), p(658, 780)]] {
                let path = NSBezierPath()
                path.move(to: points[0])
                points.dropFirst().forEach { path.line(to: $0) }
                // Thinner than the app icon's 124 so the square opening stays visible at 18 pt.
                path.lineWidth = 88 * scale
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                NSColor.black.setStroke()
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Reticle"
        return image
    }
}
