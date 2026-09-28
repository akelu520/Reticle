import AppKit

enum CaptureMode: Equatable {
    case screenshot
    case scrollCapture
    case recognizeText
    /// 录屏: select a region, then record it.
    case record
}

/// Mode switcher at the top of the screen while no selection exists:
/// ⠿ 截图 滚动截图 录屏 提取文字 — dark bar, text only, the current mode as a white pill.
final class ModeBar: NSView {
    private static let order: [(CaptureMode, String)] = [
        (.screenshot, "截图"), (.scrollCapture, "滚动截图"), (.record, "录屏"), (.recognizeText, "提取文字"),
    ]
    private static let background = NSColor(srgbRed: 0x07 / 255, green: 0x14 / 255, blue: 0x1C / 255, alpha: 0.96)

    private let stack = NSStackView()
    private var buttons: [(CaptureMode, ModeButton)] = []
    private let onSelect: (CaptureMode) -> Void
    /// Dragging the ⠿ handle moves the bar.
    var onDrag: ((CGVector) -> Void)?

    init(onSelect: @escaping (CaptureMode) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Self.background.cgColor
        layer?.cornerRadius = 12
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        stack.addArrangedSubview(DragHandle(dark: true) { [weak self] d in self?.onDrag?(d) })
        for (mode, title) in Self.order {
            let b = ModeButton(title: title) { [weak self] in self?.onSelect(mode) }
            buttons.append((mode, b))
            stack.addArrangedSubview(b)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {}

    func update(mode: CaptureMode) {
        for (m, b) in buttons { b.isCurrent = m == mode }
    }
}

/// One mode: white text, or black text on a white pill when current.
final class ModeButton: NSView {
    private let label = NSTextField(labelWithString: "")
    private let action: () -> Void
    var isCurrent = false { didSet { refresh() } }

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        label.stringValue = title
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 33),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var title: String { label.stringValue }

    private func refresh() {
        layer?.backgroundColor = isCurrent ? NSColor.white.cgColor : nil
        label.textColor = isCurrent ? .black : .white
    }

    override func mouseDown(with event: NSEvent) { action() }

    /// Lets tests trigger it like a button.
    func performClick() { action() }
}
