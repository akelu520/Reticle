import AppKit

/// Non-blocking error notice: a floating panel with a message and 好, auto-hiding after a
/// few seconds. Used for failures that happen without user interaction (e.g. a capture
/// that fails right after the hotkey): a modal alert from a background accessory app can
/// end up invisible while still blocking the app.
@MainActor
enum ErrorHUD {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ title: String, _ message: String) {
        print("[Reticle] \(title)：\(message)")
        panel?.orderOut(nil)
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 340, height: 108))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        content.layer?.cornerRadius = 10
        content.appearance = NSAppearance(named: .aqua)
        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.frame = CGRect(x: 18, y: 72, width: 304, height: 20)
        let body = NSTextField(wrappingLabelWithString: message)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.frame = CGRect(x: 18, y: 34, width: 304, height: 36)
        let ok = NSButton(title: "好", target: HUDTarget.shared, action: #selector(HUDTarget.dismiss))
        ok.bezelStyle = .rounded
        ok.frame = CGRect(x: 262, y: 6, width: 64, height: 28)
        [titleField, body, ok].forEach(content.addSubview)

        let p = NSPanel(contentRect: content.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = content
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            p.setFrameOrigin(CGPoint(x: f.midX - content.frame.width / 2, y: f.maxY - content.frame.height - 60))
        }
        p.orderFrontRegardless()
        panel = p
        hideWork?.cancel()
        let work = DispatchWorkItem { dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Whether a notice is on screen (tests).
    static var isVisible: Bool { panel?.isVisible == true }
}

private final class HUDTarget: NSObject {
    static let shared = HUDTarget()
    @MainActor @objc func dismiss() { ErrorHUD.dismiss() }
}
