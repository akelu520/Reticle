import AppKit
import ReticleCore

/// 水印 options in sub-toolbar form: text (最多输入 16 个字符) ｜ 不透明度 ｜ 颜色.
/// Changes preview live; Return or clicking elsewhere applies them.
final class WatermarkPanel: FloatingPanelView, NSTextFieldDelegate {
    struct Value {
        var text: String
        var opacity: CGFloat
        var color: RGBA
    }

    private let field = NSTextField()
    private let percent = NSTextField(labelWithString: "30 %")
    private var slider: PercentSlider!
    private var swatches: [ColorSwatch] = []
    private var color: RGBA = .red
    private var opacity = Watermark.defaultOpacity
    private let onChange: (Value) -> Void
    private let onDone: () -> Void

    init(onChange: @escaping (Value) -> Void, onDone: @escaping () -> Void) {
        self.onChange = onChange
        self.onDone = onDone
        super.init(spacing: 8, insets: NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))

        field.placeholderString = "最多输入 \(Watermark.maxLength) 个字符"
        field.delegate = self
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 170).isActive = true
        stack.addArrangedSubview(field)
        addSeparator()

        let title = NSTextField(labelWithString: "不透明度")
        title.font = .systemFont(ofSize: 13)
        title.textColor = Palette.icon
        stack.addArrangedSubview(title)
        percent.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        percent.textColor = Palette.icon
        percent.alignment = .right
        slider = PercentSlider(value: opacity, percent: percent) { [weak self] v in
            self?.opacity = max(v, 0.05)
            self?.notify()
        }
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        stack.addArrangedSubview(slider)
        percent.translatesAutoresizingMaskIntoConstraints = false
        percent.widthAnchor.constraint(equalToConstant: 46).isActive = true
        stack.addArrangedSubview(percent)
        addSeparator()

        for c in RGBA.palette {
            let s = ColorSwatch(color: c) { [weak self] in self?.pick(c) }
            swatches.append(s)
            stack.addArrangedSubview(s)
        }
        refreshSwatches()
    }

    func load(_ w: Watermark?) {
        field.stringValue = w?.text ?? ""
        opacity = w?.opacity ?? Watermark.defaultOpacity
        slider.doubleValue = Double(opacity)
        percent.stringValue = "\(Int((opacity * 100).rounded())) %"
        color = w?.color ?? .red
        refreshSwatches()
    }

    func focus() {
        window?.makeFirstResponder(field)
    }

    /// Tests type into the field.
    func setTextForTesting(_ text: String) {
        field.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    private var value: Value {
        Value(text: field.stringValue, opacity: opacity, color: color)
    }

    private func notify() { onChange(value) }

    private func pick(_ c: RGBA) {
        color = c
        refreshSwatches()
        notify()
    }

    private func refreshSwatches() {
        for s in swatches { s.isSelected = s.color == color }
    }

    func controlTextDidChange(_ obj: Notification) {
        let limited = Watermark.limited(field.stringValue)
        if limited != field.stringValue { field.stringValue = limited }
        notify()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            onDone()
            return true
        }
        return false
    }
}
