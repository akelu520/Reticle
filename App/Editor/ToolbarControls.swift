import AppKit
import ReticleCore

enum Palette {
    static let accent = NSColor(srgbRed: 0x33 / 255, green: 0x70 / 255, blue: 1, alpha: 1)
    static let selectedBackground = NSColor(srgbRed: 0x33 / 255, green: 0x70 / 255, blue: 1, alpha: 0.12)
}

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// White rounded floating panel used by the main toolbar, sub toolbar and watermark panel.
class FloatingPanelView: NSView {
    let stack = NSStackView()

    init(spacing: CGFloat = 2) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 6
        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 8
            s.shadowOffset = CGSize(width: 0, height: -2)
            s.shadowColor = NSColor.black.withAlphaComponent(0.3)
            return s
        }()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
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
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 20).isActive = true
        stack.addArrangedSubview(line)
    }
}

/// Square icon button with a selected state and a closure action.
final class IconButton: NSButton {
    private let handler: () -> Void
    var isSelectedTool = false { didSet { refresh() } }
    var baseTint: NSColor = .labelColor { didSet { refresh() } }

    init(symbol: String, tip: String, size: CGFloat = 32, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = tip
        target = self
        action = #selector(fire)
        wantsLayer = true
        layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        refresh()
    }

    /// Text-only variant (e.g. font size "A").
    convenience init(title: String, fontSize: CGFloat, tip: String, handler: @escaping () -> Void) {
        self.init(symbol: "", tip: tip, size: 28, handler: handler)
        image = nil
        imagePosition = .noImage
        attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.35 } }

    private func refresh() {
        contentTintColor = isSelectedTool ? Palette.accent : baseTint
        layer?.backgroundColor = isSelectedTool ? Palette.selectedBackground.cgColor : nil
    }

    @objc private func fire() { handler() }
}

/// Round color swatch with a ring when selected.
final class ColorSwatch: NSView {
    let color: RGBA
    private let handler: () -> Void
    var isSelected = false { didSet { needsDisplay = true } }

    init(color: RGBA, handler: @escaping () -> Void) {
        self.color = color
        self.handler = handler
        super.init(frame: .zero)
        toolTip = nil
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 22), heightAnchor.constraint(equalToConstant: 22)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let dot = bounds.insetBy(dx: 5, dy: 5)
        color.nsColor.setFill()
        NSBezierPath(ovalIn: dot).fill()
        if color.isLight {
            NSColor(white: 0.8, alpha: 1).setStroke()
            NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
        if isSelected {
            Palette.accent.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

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
        wantsLayer = true
        layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 24), heightAnchor.constraint(equalToConstant: 24)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        layer?.backgroundColor = isSelected ? Palette.selectedBackground.cgColor : nil
        (isSelected ? Palette.accent : NSColor(white: 0.45, alpha: 1)).setFill()
        let r = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        NSBezierPath(ovalIn: r).fill()
    }

    override func mouseDown(with event: NSEvent) { handler() }
}
