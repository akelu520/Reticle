import AppKit

/// Shown after selecting a region in 滚动截图 mode: selection guidance plus
/// 开始滚动截图 / 取消.
final class ScrollStartBar: FloatingPanelView {
    private let onStart: () -> Void
    private let onCancel: () -> Void

    init(onStart: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onStart = onStart
        self.onCancel = onCancel
        super.init(spacing: 8)
        let hint = NSTextField(wrappingLabelWithString: "请只框选会滚动的内容，避开滚动条、固定不动的元素和视频动画")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.widthAnchor.constraint(equalToConstant: 230).isActive = true
        stack.addArrangedSubview(hint)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        stack.addArrangedSubview(cancel)
        let start = NSButton(title: "开始滚动截图", target: self, action: #selector(startTapped))
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        stack.addArrangedSubview(start)
    }

    @objc private func startTapped() { onStart() }
    @objc private func cancelTapped() { onCancel() }
}
