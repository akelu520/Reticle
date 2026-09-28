import AppKit
import ReticleCore

/// Options for the active tool or the selected annotation. A small caret on the
/// edge facing the main toolbar points at the tool it belongs to.
///
/// - 形状 / 画笔: 粗细 ｜ 颜色
/// - 文本: 样式（普通 / 底色 / 描边）｜ 字号 ▾ ｜ 颜色
/// - 标签: 字号 ▾ ｜ 颜色
/// - 马赛克: 马赛克 / 模糊 ｜ 画笔 ▾ / 框选 ｜ 模糊强度
/// - 高亮: 矩形 / 椭圆 / 圆角矩形 ｜ 不透明度
final class SubToolbar: FloatingPanelView {
    struct Actions {
        var setSize: (SizeLevel) -> Void
        var setColor: (RGBA) -> Void
        var setMosaicMode: (MosaicMode) -> Void
        var setFontSize: (CGFloat) -> Void
        var setTextStyle: (TextStyle) -> Void
        var setEffect: (MosaicEffect) -> Void
        var setStrength: (CGFloat) -> Void
        var setShape: (HighlightShape) -> Void
        var setOpacity: (CGFloat) -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        super.init(spacing: 8, insets: NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))
    }

    private struct Config: Equatable {
        var tool: Tool
        var preset: ToolPreset
        var mosaicMode: MosaicMode
    }

    private var config: Config?

    /// Rebuilds the controls only when something changed.
    func configure(tool: Tool, preset: ToolPreset, mosaicMode: MosaicMode) {
        let next = Config(tool: tool, preset: preset, mosaicMode: mosaicMode)
        guard next != config else { return }
        config = next
        for v in stack.arrangedSubviews { v.removeFromSuperview() }

        switch tool {
        case .mosaic:
            let a = actions
            addChoice([("reticle.mosaic", "马赛克", preset.effect == .mosaic, { a.setEffect(.mosaic) }),
                       ("drop", "模糊", preset.effect == .blur, { a.setEffect(.blur) })])
            addSeparator()
            let brush = IconButton(symbol: "hand.point.up.left", tip: "画笔", size: 28) { a.setMosaicMode(.brush) }
            brush.isSelectedTool = mosaicMode == .brush
            stack.addArrangedSubview(brush)
            let sizes = MenuButton(title: nil, tip: "画笔粗细") { [weak self] in self?.brushSizeMenu(selected: preset.size) }
            stack.addArrangedSubview(sizes)
            stack.setCustomSpacing(0, after: brush)
            let box = IconButton(symbol: "rectangle.dashed", tip: "框选", size: 28) { a.setMosaicMode(.box) }
            box.isSelectedTool = mosaicMode == .box
            stack.addArrangedSubview(box)
            addSeparator()
            addSlider(title: "模糊强度", value: preset.strength, apply: a.setStrength)
        case .highlight:
            let a = actions
            addChoice([("square", "矩形", preset.shape == .rect, { a.setShape(.rect) }),
                       ("circle", "椭圆", preset.shape == .ellipse, { a.setShape(.ellipse) }),
                       ("app", "圆角矩形", preset.shape == .roundedRect, { a.setShape(.roundedRect) })])
            addSeparator()
            addSlider(title: "不透明度", value: preset.opacity, apply: a.setOpacity)
        case .text:
            let a = actions
            addChoice([("reticle.text", "普通", preset.textStyle == .plain, { a.setTextStyle(.plain) }),
                       ("reticle.textBox", "底色", preset.textStyle == .background, { a.setTextStyle(.background) }),
                       ("reticle.textOutline", "描边", preset.textStyle == .outline, { a.setTextStyle(.outline) })])
            addFontSize(preset.fontSize)
            addSeparator()
            addColors(preset.color)
        case .label:
            addFontSize(preset.fontSize)
            addSeparator()
            addColors(preset.color)
        default:
            addSizeDots(selected: preset.size)
            addSeparator()
            addColors(preset.color)
        }
    }

    private func addChoice(_ items: [(String, String, Bool, () -> Void)]) {
        for (symbol, tip, on, action) in items {
            let b = IconButton(symbol: symbol, tip: tip, size: 28, handler: action)
            b.isSelectedTool = on
            stack.addArrangedSubview(b)
        }
    }

    private func addColors(_ selected: RGBA) {
        for color in RGBA.palette {
            let swatch = ColorSwatch(color: color) { [actions] in actions.setColor(color) }
            swatch.isSelected = color == selected
            stack.addArrangedSubview(swatch)
        }
    }

    private func addSizeDots(selected: SizeLevel) {
        for (level, d) in [(SizeLevel.small, 5.0), (.medium, 9.0), (.large, 12.0)] {
            let dot = SizeDot(diameter: d) { [actions] in actions.setSize(level) }
            dot.isSelected = level == selected
            dot.setAccessibilityLabel(["细", "中", "粗"][level.rawValue])
            stack.addArrangedSubview(dot)
        }
    }

    /// "12pt ⌄" menu.
    private func addFontSize(_ points: CGFloat) {
        let button = MenuButton(title: "\(Int(points))pt", tip: "字号") { [weak self] in self?.fontSizeMenu(selected: points) }
        stack.addArrangedSubview(button)
    }

    private func fontSizeMenu(selected: CGFloat) -> NSMenu {
        let menu = NSMenu()
        for size in EditorModel.fontSizeChoices {
            let item = MenuActionItem(title: "\(Int(size))pt") { [actions] in actions.setFontSize(size) }
            item.state = size == selected ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func brushSizeMenu(selected: SizeLevel) -> NSMenu {
        let menu = NSMenu()
        for level in SizeLevel.allCases {
            let item = MenuActionItem(title: ["细", "中", "粗"][level.rawValue]) { [actions] in actions.setSize(level) }
            item.state = level == selected ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    /// Title, slider and a live percentage; the value is applied when the drag ends.
    private func addSlider(title: String, value: CGFloat, apply: @escaping (CGFloat) -> Void) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = Palette.icon
        stack.addArrangedSubview(label)
        let percent = NSTextField(labelWithString: "\(Int((value * 100).rounded())) %")
        percent.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        percent.textColor = Palette.icon
        percent.alignment = .right
        let slider = PercentSlider(value: value, percent: percent, apply: apply)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        stack.addArrangedSubview(slider)
        percent.translatesAutoresizingMaskIntoConstraints = false
        percent.widthAnchor.constraint(equalToConstant: 46).isActive = true
        stack.addArrangedSubview(percent)
    }

    /// The caret sits just outside the panel, so it is drawn by a sibling (see `CaretView`).
    static let caretHeight: CGFloat = 6
}

/// A slider that updates its percentage live and applies the value when released.
final class PercentSlider: NSSlider {
    private let percent: NSTextField
    private let apply: (CGFloat) -> Void

    init(value: CGFloat, percent: NSTextField, apply: @escaping (CGFloat) -> Void) {
        self.percent = percent
        self.apply = apply
        super.init(frame: .zero)
        minValue = 0
        maxValue = 1
        doubleValue = Double(value)
        controlSize = .small
        isContinuous = true
        target = self
        action = #selector(changed)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() {
        percent.stringValue = "\(Int((doubleValue * 100).rounded())) %"
        // One undo step per drag: apply on release (or on a click without drag).
        if let type = NSApp.currentEvent?.type, type == .leftMouseDragged { return }
        apply(CGFloat(doubleValue))
    }

    /// Tests set the value directly.
    func set(_ value: CGFloat) {
        doubleValue = Double(value)
        percent.stringValue = "\(Int((value * 100).rounded())) %"
        apply(value)
    }
}

/// "12pt ⌄" style button that pops up a menu.
final class MenuButton: NSButton {
    private let makeMenu: () -> NSMenu?
    let tip: String

    init(title: String?, tip: String, makeMenu: @escaping () -> NSMenu?) {
        self.makeMenu = makeMenu
        self.tip = tip
        super.init(frame: .zero)
        setAccessibilityLabel(tip)
        isBordered = false
        wantsLayer = true
        if let title {
            attributedTitle = NSAttributedString(string: "\(title)  ⌄", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Palette.icon])
            layer?.borderWidth = 1
            layer?.borderColor = Palette.swatchBorder.cgColor
            layer?.cornerRadius = 5
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 26), widthAnchor.constraint(greaterThanOrEqualToConstant: 72)])
        } else {
            image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: tip)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .regular))
            contentTintColor = Palette.icon
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 14), heightAnchor.constraint(equalToConstant: 26)])
        }
        target = self
        action = #selector(open)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func open() {
        guard let menu = makeMenu() else { return }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.height + 4), in: self)
    }

    /// Tests pick an item without showing the menu.
    func menuForTesting() -> NSMenu? { makeMenu() }
}

/// Menu item running a closure.
final class MenuActionItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc func fire() { run() }
}

/// Small white triangle between the toolbar and a sub toolbar, pointing at the tool.
final class CaretView: NSView {
    /// True when the sub toolbar is below the toolbar (the caret points up).
    var pointsUp = true { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        let p = NSBezierPath()
        let base = pointsUp ? bounds.maxY : 0, tip = pointsUp ? 0 : bounds.maxY
        p.move(to: CGPoint(x: 0, y: base))
        p.line(to: CGPoint(x: bounds.midX, y: tip))
        p.line(to: CGPoint(x: bounds.maxX, y: base))
        p.close()
        p.fill()
    }
}
