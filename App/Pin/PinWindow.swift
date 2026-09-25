import AppKit
import ReticleCore

/// 固定到屏幕：the screenshot floats above other windows. Drag to move,
/// double-click or Esc to close, right-click for copy / save / close.
final class PinWindow: NSPanel {
    let image: CGImage
    var onClose: ((PinWindow) -> Void)?

    init(image: CGImage, frame: CGRect, scale: CGFloat) {
        self.image = image
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
        let content = PinContentView(image: image)
        content.layer?.contentsScale = scale
        content.frame = CGRect(origin: .zero, size: frame.size)
        contentView = content
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    func dismiss() {
        orderOut(nil)
        onClose?(self)
    }

    @objc func copyImage() {
        _ = OutputService.copyToPasteboard(image)
    }

    @objc func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = Preferences.saveDirectory
        panel.nameFieldStringValue = FileNaming.screenshotName(for: Date())
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try OutputService.write(image, to: url)
            Preferences.saveDirectory = url.deletingLastPathComponent()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func closeFromMenu() { dismiss() }
}

private final class PinContentView: NSView {
    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        // Draw pixels 1:1; a half-point window rounding must not resample the image.
        layer?.contentsGravity = .center
        layer?.borderColor = Palette.accent.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (window as? PinWindow)?.dismiss()
            return
        }
        window?.makeKey()
        window?.performDrag(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let pin = window as? PinWindow else { return nil }
        let menu = NSMenu()
        for (title, action) in [("复制", #selector(PinWindow.copyImage)), ("保存…", #selector(PinWindow.saveImage)), ("关闭", #selector(PinWindow.closeFromMenu))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = pin
            menu.addItem(item)
        }
        return menu
    }
}

/// Keeps pinned windows alive until they are closed.
@MainActor
final class PinManager {
    static let shared = PinManager()
    private var windows: [PinWindow] = []

    func pin(_ image: CGImage, frame: CGRect, scale: CGFloat) {
        // Size the window to the image's pixels so it is shown 1:1, never resampled.
        let exact = CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(),
                           width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let w = PinWindow(image: image, frame: exact, scale: scale)
        w.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        windows.append(w)
        w.orderFrontRegardless()
    }
}
