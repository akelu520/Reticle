import AppKit
import ReticleCore

/// Draws the annotations inside the selection. Its frame is the selection, so
/// its backing store stays as small as the selection rather than the screen.
final class AnnotationCanvasView: NSView {
    struct Content {
        var annotations: [Annotation]
        var watermark: Watermark?
        var selectedBounds: CGRect?
    }

    var content = Content(annotations: [], watermark: nil, selectedBounds: nil) { didSet { needsDisplay = true } }
    var pixelated: CGImage? { didSet { needsDisplay = true } }
    private let baseSize: CGSize
    private let scale: CGFloat

    init(baseSize: CGSize, scale: CGFloat) {
        self.baseSize = baseSize
        self.scale = scale
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        // View origin is the selection's top-left; move into screen-local points, then pixels.
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        AnnotationRenderer.draw(content.annotations, pixelated: pixelated, baseSize: baseSize, in: ctx)
        if let w = content.watermark {
            AnnotationRenderer.drawWatermark(w, in: CoordinateSpace.pixelRect(fromPoints: frame, scale: scale), ctx: ctx)
        }
        ctx.restoreGState()

        if let b = content.selectedBounds {
            let r = CGRect(x: b.minX / scale - frame.minX, y: b.minY / scale - frame.minY, width: b.width / scale, height: b.height / scale)
                .insetBy(dx: -3, dy: -3)
            let path = NSBezierPath(rect: r)
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            Palette.accent.setStroke()
            path.stroke()
        }
    }
}
