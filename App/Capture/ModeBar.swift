import AppKit

enum CaptureMode: Equatable {
    case screenshot
    case scrollCapture
    case recognizeText
    /// 录屏 (⌥⇧R): select a region, then record it. Not on the mode bar.
    case record
}

/// Top-of-screen mode switcher shown before a selection exists (截图 / 滚动截图 / 提取文字).
final class ModeBar: FloatingPanelView {
    private var buttons: [(CaptureMode, NSButton)] = []
    private let onSelect: (CaptureMode) -> Void

    init(onSelect: @escaping (CaptureMode) -> Void) {
        self.onSelect = onSelect
        super.init(spacing: 4)
        add(.screenshot, title: "截图", symbol: "viewfinder")
        add(.scrollCapture, title: "滚动截图", symbol: "arrow.up.and.down.text.horizontal")
        add(.recognizeText, title: "提取文字", symbol: "text.viewfinder")
    }

    private func add(_ mode: CaptureMode, title: String, symbol: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(config)
        let b = NSButton(title: title, image: image ?? NSImage(), target: self, action: #selector(tapped(_:)))
        b.imagePosition = .imageLeading
        b.isBordered = false
        b.font = .systemFont(ofSize: 13)
        b.tag = buttons.count
        b.wantsLayer = true
        b.layer?.cornerRadius = 4
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        buttons.append((mode, b))
        stack.addArrangedSubview(b)
    }

    func update(mode: CaptureMode) {
        for (m, b) in buttons {
            let on = m == mode
            b.contentTintColor = on ? Palette.accent : .labelColor
            b.layer?.backgroundColor = on ? Palette.selectedBackground.cgColor : nil
        }
    }

    @objc private func tapped(_ sender: NSButton) {
        onSelect(buttons[sender.tag].0)
    }
}
