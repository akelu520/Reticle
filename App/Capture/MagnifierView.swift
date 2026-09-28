import AppKit

/// Loupe beside the cursor: 17×17 source pixels enlarged to ~144 pt with a thin
/// crosshair, and a dark panel below with the pixel coordinate, the color under
/// the cursor, and the ⌘C / Shift hints.
final class MagnifierView: NSView {
    private static let samplePixels = 17
    private static let zoom: CGFloat = 8.5
    private static let infoHeight: CGFloat = 78
    static var side: CGFloat { CGFloat(samplePixels) * zoom }

    private let image: CGImage
    private let scale: CGFloat
    private var center = CGPoint.zero
    /// Color under the cursor, 0–255.
    private(set) var color: (r: Int, g: Int, b: Int) = (0, 0, 0)
    /// Shift toggles between RGB and HEX.
    var showsHex = false { didSet { needsDisplay = true } }

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side + Self.infoHeight))
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The color as shown ("120,170,203" or "#78AACB"), for ⌘C.
    var colorString: String {
        showsHex ? String(format: "#%02X%02X%02X", color.r, color.g, color.b) : "\(color.r),\(color.g),\(color.b)"
    }

    /// - Parameter cursor: cursor position in screen-local points.
    func update(cursor: CGPoint) {
        center = CGPoint(x: (cursor.x * scale).rounded(.down), y: (cursor.y * scale).rounded(.down))
        color = Self.sample(image, at: center)
        needsDisplay = true
    }

    private static func sample(_ image: CGImage, at p: CGPoint) -> (Int, Int, Int) {
        guard p.x >= 0, p.y >= 0, Int(p.x) < image.width, Int(p.y) < image.height,
              let one = image.cropping(to: CGRect(x: p.x, y: p.y, width: 1, height: 1)) else { return (0, 0, 0) }
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let n = Self.samplePixels
        let side = Self.side

        NSColor.black.setFill()
        CGRect(x: 0, y: 0, width: side, height: side).fill()

        // Sample the pixels around the cursor; parts outside the image stay black.
        let half = CGFloat(n / 2)
        let src = CGRect(x: center.x - half, y: center.y - half, width: CGFloat(n), height: CGFloat(n))
        let clipped = src.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if !clipped.isNull, let crop = image.cropping(to: clipped) {
            let dest = CGRect(x: (clipped.minX - src.minX) * Self.zoom, y: (clipped.minY - src.minY) * Self.zoom,
                              width: clipped.width * Self.zoom, height: clipped.height * Self.zoom)
            ctx.saveGState()
            ctx.interpolationQuality = .none
            // The view is flipped; flip the image back so it draws upright.
            ctx.translateBy(x: 0, y: dest.maxY + dest.minY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(crop, in: dest)
            ctx.restoreGState()
        }

        // Thin crosshair through the center pixel, which is outlined.
        let c = half * Self.zoom
        ctx.setFillColor(Palette.accent.withAlphaComponent(0.75).cgColor)
        ctx.fill(CGRect(x: c + Self.zoom / 2 - 1.5, y: 0, width: 3, height: side))
        ctx.fill(CGRect(x: 0, y: c + Self.zoom / 2 - 1.5, width: side, height: 3))
        let pixel = CGRect(x: c, y: c, width: Self.zoom, height: Self.zoom).insetBy(dx: 0.5, dy: 0.5)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(pixel)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(pixel.insetBy(dx: 1, dy: 1))

        // Info panel.
        let panel = CGRect(x: 0, y: side, width: side, height: Self.infoHeight)
        NSColor(white: 0.08, alpha: 0.88).setFill()
        panel.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let valueText = showsHex ? String(format: "HEX:#%02X%02X%02X", color.r, color.g, color.b) : "RGB:\(color.r),\(color.g),\(color.b)"
        let lines = ["坐标: \(Int(center.x)),\(Int(center.y))", valueText, "按 ⌘ + C 复制色值", "按 Shift 切换 RGB/HEX"]
        let lineHeight: CGFloat = 17.5
        for (i, line) in lines.enumerated() {
            let text = line as NSString
            let size = text.size(withAttributes: attrs)
            var x = (side - size.width) / 2
            let y = panel.minY + 4 + CGFloat(i) * lineHeight + (lineHeight - size.height) / 2
            if i == 1 {
                // Swatch of the sampled color before the value.
                x += 6
                let swatch = CGRect(x: x - 12, y: y + (size.height - 8) / 2, width: 8, height: 8)
                NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1).setFill()
                swatch.fill()
                NSColor(white: 1, alpha: 0.6).setStroke()
                NSBezierPath(rect: swatch.insetBy(dx: 0.5, dy: 0.5)).stroke()
            }
            text.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        }
    }
}
