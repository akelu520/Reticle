import AppKit

/// Floating controls during a scroll capture: live preview of the stitched
/// image, status, 自动滚动 / 停止滚动, 完成, 取消.
final class ScrollControlPanel: NSPanel {
    struct Actions {
        var toggleAutoScroll: () -> Void
        var finish: () -> Void
        var cancel: () -> Void
    }

    static let previewWidth: CGFloat = 120
    private static let previewHeight: CGFloat = 260

    private let actions: Actions
    private let preview = NSImageView()
    private let status = NSTextField(wrappingLabelWithString: "正在准备…")
    private let autoButton = NSButton(title: "自动滚动", target: nil, action: nil)

    init(actions: Actions) {
        self.actions = actions
        let size = CGSize(width: Self.previewWidth + 24, height: Self.previewHeight + 150)
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let root = NSView(frame: CGRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        root.layer?.cornerRadius = 8
        root.appearance = NSAppearance(named: .aqua)
        contentView = root

        let previewBox = NSView(frame: CGRect(x: 12, y: size.height - 12 - Self.previewHeight, width: Self.previewWidth, height: Self.previewHeight))
        previewBox.wantsLayer = true
        previewBox.layer?.backgroundColor = NSColor(white: 0.95, alpha: 1).cgColor
        previewBox.layer?.cornerRadius = 4
        previewBox.layer?.masksToBounds = true
        root.addSubview(previewBox)
        preview.imageScaling = .scaleProportionallyDown
        preview.imageAlignment = .alignBottom
        preview.frame = previewBox.bounds
        previewBox.addSubview(preview)

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        status.frame = CGRect(x: 8, y: 104, width: size.width - 16, height: 32)
        root.addSubview(status)

        var y: CGFloat = 72
        for (button, action) in [(autoButton, #selector(autoTapped)),
                                 (NSButton(title: "完成", target: nil, action: nil), #selector(finishTapped)),
                                 (NSButton(title: "取消", target: nil, action: nil), #selector(cancelTapped))] {
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
            button.frame = CGRect(x: 12, y: y, width: size.width - 24, height: 28)
            root.addSubview(button)
            y -= 32
        }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { actions.cancel() }

    func setStatus(_ text: String) { status.stringValue = text }

    func setPreview(_ image: CGImage, scale: CGFloat) {
        preview.image = NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
    }

    func setAutoScrolling(_ on: Bool) {
        autoButton.title = on ? "停止滚动" : "自动滚动"
    }

    func hideAutoScroll() { autoButton.isHidden = true }

    @objc private func autoTapped() { actions.toggleAutoScroll() }
    @objc private func finishTapped() { actions.finish() }
    @objc private func cancelTapped() { actions.cancel() }
}
