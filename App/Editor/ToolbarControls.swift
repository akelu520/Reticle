import AppKit
import ReticleCore

enum Palette {
    static let accent = NSColor(srgbRed: 0x33 / 255, green: 0x6D / 255, blue: 0xF4 / 255, alpha: 1)
    static let selectedBackground = accent.withAlphaComponent(0.12)
    static let neutral = NSColor(srgbRed: 0x8F / 255, green: 0x95 / 255, blue: 0x9E / 255, alpha: 1)
    static let icon = NSColor(srgbRed: 0x1F / 255, green: 0x23 / 255, blue: 0x29 / 255, alpha: 1)
    static let danger = NSColor(srgbRed: 0xF6 / 255, green: 0x4A / 255, blue: 0x45 / 255, alpha: 1)
    static let success = NSColor(srgbRed: 0x34 / 255, green: 0xBE / 255, blue: 0x4B / 255, alpha: 1)
    static let tooltip = NSColor(srgbRed: 0x1F / 255, green: 0x23 / 255, blue: 0x2A / 255, alpha: 1)
    static let swatchBorder = NSColor(srgbRed: 0xD1 / 255, green: 0xD3 / 255, blue: 0xD6 / 255, alpha: 1)
}

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// White rounded floating panel used by the main toolbar and sub toolbar.
class FloatingPanelView: NSView {
    let stack = NSStackView()
    /// Called while the ⠿ handle is dragged, with the mouse delta in the parent's (flipped) space.
    var onDrag: ((CGVector) -> Void)?

    init(spacing: CGFloat = 4, insets: NSEdgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8
        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 10
            s.shadowOffset = CGSize(width: 0, height: -2)
            s.shadowColor = NSColor.black.withAlphaComponent(0.22)
            return s
        }()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.edgeInsets = insets
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Keep the panels light even in dark mode, like the rest of the capture UI.
    override func viewDidMoveToWindow() {
        appearance = NSAppearance(named: .aqua)
    }

    // Clicks on the panel background must not fall through to the overlay.
    override func mouseDown(with event: NSEvent) {}

    func addSeparator() {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 0, alpha: 0.1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.widthAnchor.constraint(equalToConstant: 1), line.heightAnchor.constraint(equalToConstant: 20)])
        stack.addArrangedSubview(line)
    }

    /// ⠿ at the leading edge; dragging it moves the panel via `onDrag`.
    func addDragHandle(dark: Bool = false) {
        let handle = DragHandle(dark: dark) { [weak self] d in self?.onDrag?(d) }
        stack.addArrangedSubview(handle)
    }
}

/// Six-dot grip that reports drags.
final class DragHandle: NSView {
    private let dark: Bool
    private let onDrag: (CGVector) -> Void
    private var last: CGPoint?

    init(dark: Bool, onDrag: @escaping (CGVector) -> Void) {
        self.dark = dark
        self.onDrag = onDrag
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 16), heightAnchor.constraint(equalToConstant: 28)])
        setAccessibilityLabel("拖动")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        (dark ? NSColor(white: 1, alpha: 0.35) : Palette.neutral).setFill()
        for col in 0..<2 {
            for row in 0..<3 {
                let c = CGPoint(x: bounds.midX - 2.5 + CGFloat(col) * 5, y: bounds.midY - 5 + CGFloat(row) * 5)
                NSBezierPath(ovalIn: CGRect(x: c.x - 1.1, y: c.y - 1.1, width: 2.2, height: 2.2)).fill()
            }
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    // Toolbar clicks work even while the overlay is not the key window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        last = event.locationInWindow
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last else { return }
        let p = event.locationInWindow
        // Window space is y-up; panels live in flipped overlays.
        onDrag(CGVector(dx: p.x - last.x, dy: -(p.y - last.y)))
        self.last = p
    }

    override func mouseUp(with event: NSEvent) { last = nil }
}

/// Square icon button with a selected state, a closure action and a dark hover tooltip.
final class IconButton: NSButton {
    private let handler: () -> Void
    /// Tooltip text; also the accessibility label.
    let tip: String
    var isSelectedTool = false { didSet { refresh() } }
    var baseTint: NSColor = Palette.icon { didSet { refresh() } }
    private var tracking: NSTrackingArea?

    init(symbol: String, tip: String, size: CGFloat = 32, pointSize: CGFloat = 18, handler: @escaping () -> Void) {
        self.handler = handler
        self.tip = tip
        super.init(frame: .zero)
        image = Icons.image(symbol, pointSize: pointSize, description: tip)
        imagePosition = .imageOnly
        isBordered = false
        setAccessibilityLabel(tip)
        target = self
        action = #selector(fire)
        wantsLayer = true
        layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        refresh()
    }

    /// Text-only variant (e.g. a text style "T").
    convenience init(title: String, fontSize: CGFloat, tip: String, handler: @escaping () -> Void) {
        self.init(symbol: "", tip: tip, size: 28, handler: handler)
        image = nil
        imagePosition = .noImage
        attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isEnabled: Bool { didSet { refresh() } }

    private func refresh() {
        contentTintColor = !isEnabled ? Palette.neutral.withAlphaComponent(0.55) : isSelectedTool ? Palette.accent : baseTint
        layer?.backgroundColor = isSelectedTool ? Palette.selectedBackground.cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { Tooltip.shared.schedule(tip, for: self) }
    override func mouseExited(with event: NSEvent) { Tooltip.shared.hide() }

    @objc private func fire() {
        Tooltip.shared.hide()
        handler()
    }
}

/// Toolbar glyphs: SF Symbols where one matches, otherwise drawn here.
enum Icons {
    static func image(_ name: String, pointSize: CGFloat, description: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let custom = custom(name, size: pointSize + 4) { return custom }
        return NSImage(systemSymbolName: name, accessibilityDescription: description)?.withSymbolConfiguration(config)
    }

    /// Template images for glyphs SF Symbols lacks.
    private static func custom(_ name: String, size: CGFloat) -> NSImage? {
        let s = CGSize(width: size, height: size)
        let draw: ((CGRect) -> Void)?
        switch name {
        case "reticle.text":
            draw = { r in
                // A plain serif-less "T".
                let p = NSBezierPath()
                p.lineWidth = 1.6
                p.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.maxY - r.height * 0.2))
                p.line(to: CGPoint(x: r.maxX - r.width * 0.2, y: r.maxY - r.height * 0.2))
                p.move(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.2))
                p.line(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.18))
                p.stroke()
            }
        case "reticle.textBox":
            draw = { r in
                // "T" knocked out of a filled rounded square (text on a box).
                let box = r.insetBy(dx: r.width * 0.14, dy: r.height * 0.14)
                NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5).fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                let t = NSBezierPath()
                t.lineWidth = 1.8
                t.move(to: CGPoint(x: box.minX + box.width * 0.24, y: box.maxY - box.height * 0.25))
                t.line(to: CGPoint(x: box.maxX - box.width * 0.24, y: box.maxY - box.height * 0.25))
                t.move(to: CGPoint(x: box.midX, y: box.maxY - box.height * 0.25))
                t.line(to: CGPoint(x: box.midX, y: box.minY + box.height * 0.2))
                t.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }
        case "reticle.textOutline":
            draw = { r in
                // Hollow "T" (outlined text).
                let top = r.maxY - r.height * 0.18, bar = r.height * 0.16, stem = r.width * 0.18
                let p = NSBezierPath()
                p.move(to: CGPoint(x: r.minX + r.width * 0.16, y: top))
                p.line(to: CGPoint(x: r.maxX - r.width * 0.16, y: top))
                p.line(to: CGPoint(x: r.maxX - r.width * 0.16, y: top - bar))
                p.line(to: CGPoint(x: r.midX + stem / 2, y: top - bar))
                p.line(to: CGPoint(x: r.midX + stem / 2, y: r.minY + r.height * 0.14))
                p.line(to: CGPoint(x: r.midX - stem / 2, y: r.minY + r.height * 0.14))
                p.line(to: CGPoint(x: r.midX - stem / 2, y: top - bar))
                p.line(to: CGPoint(x: r.minX + r.width * 0.16, y: top - bar))
                p.close()
                p.lineWidth = 1.2
                p.stroke()
            }
        case "reticle.watermark":
            draw = { r in
                // Three parallel diagonal strokes.
                let p = NSBezierPath()
                p.lineWidth = 1.6
                p.lineCapStyle = .round
                for i in 0..<3 {
                    let o = CGFloat(i) * r.width * 0.22
                    p.move(to: CGPoint(x: r.minX + r.width * 0.12 + o, y: r.minY + r.height * 0.22))
                    p.line(to: CGPoint(x: r.minX + r.width * 0.42 + o, y: r.maxY - r.height * 0.22))
                }
                p.stroke()
            }
        case "reticle.highlight":
            draw = { r in
                // Rounded square with a hatched circle: a spotlight.
                let box = r.insetBy(dx: r.width * 0.16, dy: r.height * 0.16)
                let outline = NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5)
                outline.lineWidth = 1.5
                outline.stroke()
                let circle = NSBezierPath(ovalIn: box.insetBy(dx: box.width * 0.2, dy: box.height * 0.2))
                circle.lineWidth = 1.4
                circle.stroke()
                NSGraphicsContext.saveGraphicsState()
                circle.addClip()
                let hatch = NSBezierPath()
                hatch.lineWidth = 1
                for i in -3...3 {
                    let x = box.midX + CGFloat(i) * 2.4
                    hatch.move(to: CGPoint(x: x - box.height, y: box.minY))
                    hatch.line(to: CGPoint(x: x + box.height, y: box.maxY + box.height))
                }
                hatch.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
        case "reticle.scroll":
            draw = { r in
                // Scissors inside a dashed rounded square.
                let box = r.insetBy(dx: r.width * 0.12, dy: r.height * 0.12)
                let outline = NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5)
                outline.lineWidth = 1.3
                outline.setLineDash([2.2, 1.8], count: 2, phase: 0)
                outline.stroke()
                let inner = box.insetBy(dx: box.width * 0.2, dy: box.height * 0.2)
                let blades = NSBezierPath()
                blades.lineWidth = 1.3
                blades.move(to: CGPoint(x: inner.minX, y: inner.maxY)); blades.line(to: CGPoint(x: inner.maxX, y: inner.minY + inner.height * 0.3))
                blades.move(to: CGPoint(x: inner.maxX, y: inner.maxY)); blades.line(to: CGPoint(x: inner.minX, y: inner.minY + inner.height * 0.3))
                blades.stroke()
                for x in [inner.minX + inner.width * 0.2, inner.maxX - inner.width * 0.2] {
                    let ring = NSBezierPath(ovalIn: CGRect(x: x - 2.2, y: inner.minY - 1.2, width: 4.4, height: 4.4))
                    ring.lineWidth = 1.2
                    ring.stroke()
                }
            }
        case "reticle.translate":
            draw = { r in
                // "A" inside two circular arrows.
                let c = CGPoint(x: r.midX, y: r.midY), radius = r.width * 0.36
                for (start, end) in [(20.0, 160.0), (200.0, 340.0)] {
                    let arc = NSBezierPath()
                    arc.lineWidth = 1.4
                    arc.appendArc(withCenter: c, radius: radius, startAngle: start, endAngle: end)
                    arc.stroke()
                    let a = end * .pi / 180
                    let tip = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
                    let head = NSBezierPath()
                    head.move(to: CGPoint(x: tip.x - 2.2 * cos(a - .pi / 2 + 0.6), y: tip.y - 2.2 * sin(a - .pi / 2 + 0.6)))
                    head.line(to: tip)
                    head.line(to: CGPoint(x: tip.x - 2.2 * cos(a + .pi / 2 - 0.6 + .pi), y: tip.y - 2.2 * sin(a + .pi / 2 - 0.6 + .pi)))
                    head.lineWidth = 1.4
                    head.stroke()
                }
                ("A" as NSString).draw(at: CGPoint(x: c.x - 3.8, y: c.y - 6), withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)])
            }
        case "reticle.mosaic":
            draw = { r in
                let box = r.insetBy(dx: r.width * 0.16, dy: r.height * 0.16)
                let outline = NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5)
                outline.lineWidth = 1.5
                outline.stroke()
                let cell = box.width / 4
                for (cx, cy) in [(1, 1), (2, 2), (1, 3), (3, 1), (3, 3)] {
                    NSBezierPath(rect: CGRect(x: box.minX + CGFloat(cx) * cell - cell / 2 - 1, y: box.minY + CGFloat(cy) * cell - cell / 2 - 1,
                                              width: cell * 0.9, height: cell * 0.9)).fill()
                }
            }
        default:
            draw = nil
        }
        guard let draw else { return nil }
        let image = NSImage(size: s, flipped: false) { r in
            NSColor.black.set()
            draw(r.insetBy(dx: 1, dy: 1))
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Dark rounded tooltip with a downward arrow, shown above a hovered button after a short delay.
@MainActor
final class Tooltip {
    static let shared = Tooltip()

    private let view = TooltipView()
    private var pending: DispatchWorkItem?

    func schedule(_ text: String, for target: NSView) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self, weak target] in
            guard let self, let target, target.window != nil else { return }
            self.show(text, above: target)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func hide() {
        pending?.cancel()
        view.removeFromSuperview()
    }

    private func show(_ text: String, above target: NSView) {
        guard let root = target.window?.contentView else { return }
        view.text = text
        let size = view.fittingSize
        let r = target.convert(target.bounds, to: root)
        // Above the button: in the (possibly flipped) root, "above" means toward the top edge.
        let top = root.isFlipped ? r.minY - 6 - size.height : r.maxY + 6
        var x = r.midX - size.width / 2
        x = min(max(x, root.bounds.minX + 4), root.bounds.maxX - size.width - 4)
        view.frame = CGRect(x: x, y: top, width: size.width, height: size.height)
        view.arrowX = r.midX - x
        view.flippedRoot = root.isFlipped
        root.addSubview(view)
    }
}

final class TooltipView: NSView {
    private let label = NSTextField(labelWithString: "")
    var arrowX: CGFloat = 0 { didSet { needsDisplay = true } }
    var flippedRoot = true { didSet { needsDisplay = true } }
    private static let arrow: CGFloat = 5

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5 - Self.arrow),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        Palette.tooltip.setFill()
        let body = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.arrow)
        NSBezierPath(roundedRect: body, xRadius: 5, yRadius: 5).fill()
        let a = NSBezierPath()
        a.move(to: CGPoint(x: arrowX - Self.arrow, y: body.maxY))
        a.line(to: CGPoint(x: arrowX, y: bounds.maxY))
        a.line(to: CGPoint(x: arrowX + Self.arrow, y: body.maxY))
        a.close()
        a.fill()
    }
}

/// Rounded-square color swatch; the selected one shows a check mark.
final class ColorSwatch: NSView {
    let color: RGBA
    private let handler: () -> Void
    var isSelected = false { didSet { needsDisplay = true } }

    init(color: RGBA, handler: @escaping () -> Void) {
        self.color = color
        self.handler = handler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 24), heightAnchor.constraint(equalToConstant: 24)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let square = CGRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18)
        let path = NSBezierPath(roundedRect: square, xRadius: 3, yRadius: 3)
        color.nsColor.setFill()
        path.fill()
        if color.isLight {
            Palette.swatchBorder.setStroke()
            let border = NSBezierPath(roundedRect: square.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            border.lineWidth = 1
            border.stroke()
        }
        if isSelected {
            let check = NSBezierPath()
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: CGPoint(x: square.minX + 4.5, y: square.midY))
            check.line(to: CGPoint(x: square.minX + 7.8, y: square.midY - 3.3))
            check.line(to: CGPoint(x: square.maxX - 4, y: square.midY + 3.6))
            (color.isLight ? Palette.icon : NSColor.white).setStroke()
            check.stroke()
        }
    }

    // Toolbar clicks work even while the overlay is not the key window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { handler() }
}

/// Dot whose diameter shows a line-width level.
final class SizeDot: NSView {
    private let diameter: CGFloat
    private let handler: () -> Void
    var isSelected = false { didSet { needsDisplay = true } }

    init(diameter: CGFloat, handler: @escaping () -> Void) {
        self.diameter = diameter
        self.handler = handler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 24), heightAnchor.constraint(equalToConstant: 24)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        (isSelected ? Palette.accent : Palette.neutral).setFill()
        let r = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        NSBezierPath(ovalIn: r).fill()
    }

    // Toolbar clicks work even while the overlay is not the key window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { handler() }
}
