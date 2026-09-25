import AppKit

/// Zoomed pixel view next to the cursor: 15×15 source pixels at 8×, with a
/// crosshair, plus the cursor coordinates or current selection size.
final class MagnifierView: NSView {
    private static let samplePixels = 15
    private static let zoom: CGFloat = 8
    private static let infoHeight: CGFloat = 22

    private let image: CGImage
    private let scale: CGFloat
    private var center = CGPoint.zero
    private var info = ""

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        let side = CGFloat(Self.samplePixels) * Self.zoom
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side + Self.infoHeight))
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.cgColor
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// - Parameters:
    ///   - cursor: cursor position in screen-local points.
    ///   - selectionSize: selection size in pixels while dragging, otherwise nil.
    func update(cursor: CGPoint, selectionSize: CGSize?) {
        center = CGPoint(x: (cursor.x * scale).rounded(.down), y: (cursor.y * scale).rounded(.down))
        if let s = selectionSize {
            info = "\(Int(s.width)) × \(Int(s.height))"
        } else {
            info = "(\(Int(center.x)), \(Int(center.y)))"
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let n = Self.samplePixels
        let side = CGFloat(n) * Self.zoom
        let loupe = CGRect(x: 0, y: 0, width: side, height: side)

        NSColor.black.setFill()
        bounds.fill()

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

        // Crosshair through the center pixel.
        let c = half * Self.zoom
        ctx.setFillColor(NSColor(srgbRed: 0x33 / 255, green: 0x70 / 255, blue: 1, alpha: 0.6).cgColor)
        ctx.fill(CGRect(x: c, y: 0, width: Self.zoom, height: side))
        ctx.fill(CGRect(x: 0, y: c, width: side, height: Self.zoom))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: c, y: c, width: Self.zoom, height: Self.zoom).insetBy(dx: 0.5, dy: 0.5))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white,
        ]
        let text = info as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: (side - size.width) / 2, y: loupe.maxY + (Self.infoHeight - size.height) / 2), withAttributes: attrs)
    }
}
