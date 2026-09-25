import AppKit
import ReticleCore

/// After selecting a region for 录屏: choose MP4 or GIF, then 开始录制.
final class RecordStartBar: FloatingPanelView {
    private let format = NSSegmentedControl(labels: ["MP4", "GIF"], trackingMode: .selectOne, target: nil, action: nil)
    private let onStart: (RecordingFormat) -> Void
    private let onCancel: () -> Void

    init(onStart: @escaping (RecordingFormat) -> Void, onCancel: @escaping () -> Void) {
        self.onStart = onStart
        self.onCancel = onCancel
        super.init(spacing: 8)
        format.selectedSegment = 0
        format.toolTip = "MP4 画质好、体积小；GIF 方便直接预览"
        stack.addArrangedSubview(format)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        stack.addArrangedSubview(cancel)
        let start = NSButton(title: "开始录制", target: self, action: #selector(startTapped))
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        stack.addArrangedSubview(start)
    }

    @objc private func startTapped() { onStart(format.selectedSegment == 1 ? .gif : .mp4) }
    @objc private func cancelTapped() { onCancel() }
}
