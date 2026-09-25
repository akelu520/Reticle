import AppKit
import ReticleCore

/// 水印：input text, opacity and color. Changes preview live; 移除 clears it.
final class WatermarkPanel: FloatingPanelView, NSTextFieldDelegate {
    struct Value {
        var text: String
        var opacity: CGFloat
        var color: RGBA
    }

    private let field = NSTextField()
    private let slider = NSSlider(value: 30, minValue: 10, maxValue: 100, target: nil, action: nil)
    private let percent = NSTextField(labelWithString: "30%")
    private var swatches: [ColorSwatch] = []
    private var color: RGBA = .black
    private let onChange: (Value) -> Void
    private let onDone: () -> Void

    init(onChange: @escaping (Value) -> Void, onDone: @escaping () -> Void) {
        self.onChange = onChange
        self.onDone = onDone
        super.init(spacing: 6)

        field.placeholderString = "输入水印内容"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 140).isActive = true
        stack.addArrangedSubview(field)
        addSeparator()

        stack.addArrangedSubview(NSTextField(labelWithString: "透明度"))
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 80).isActive = true
        stack.addArrangedSubview(slider)
        percent.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percent.translatesAutoresizingMaskIntoConstraints = false
        percent.widthAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(percent)
        addSeparator()

        for c in RGBA.palette {
            let s = ColorSwatch(color: c) { [weak self] in self?.pick(c) }
            swatches.append(s)
            stack.addArrangedSubview(s)
        }
        addSeparator()
        let remove = NSButton(title: "移除", target: self, action: #selector(removeTapped))
        remove.bezelStyle = .rounded
        stack.addArrangedSubview(remove)
        let done = NSButton(title: "确定", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        stack.addArrangedSubview(done)
        refreshSwatches()
    }

    func load(_ w: Watermark?) {
        field.stringValue = w?.text ?? ""
        slider.doubleValue = Double((w?.opacity ?? 0.3) * 100)
        color = w?.color ?? .black
        percent.stringValue = "\(Int(slider.doubleValue))%"
        refreshSwatches()
    }

    func focus() {
        window?.makeFirstResponder(field)
    }

    private var value: Value {
        Value(text: field.stringValue, opacity: CGFloat(slider.doubleValue / 100), color: color)
    }

    private func pick(_ c: RGBA) {
        color = c
        refreshSwatches()
        onChange(value)
    }

    private func refreshSwatches() {
        for s in swatches { s.isSelected = s.color == color }
    }

    func controlTextDidChange(_ obj: Notification) { onChange(value) }

    @objc private func sliderChanged() {
        percent.stringValue = "\(Int(slider.doubleValue))%"
        onChange(value)
    }

    @objc private func removeTapped() {
        field.stringValue = ""
        onChange(value)
        onDone()
    }

    @objc private func doneTapped() { onDone() }
}
