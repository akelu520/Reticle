import AppKit

extension NSAlert {
    /// Runs the alert so it is guaranteed to be on screen: menu-bar (accessory) apps
    /// triggered from the background may otherwise present an invisible modal window.
    @MainActor
    @discardableResult
    func runVisibly() -> NSApplication.ModalResponse {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        layout()
        window.level = .modalPanel
        window.collectionBehavior.insert(.canJoinAllSpaces)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame, size = window.frame.size
            window.setFrameOrigin(CGPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2 + f.height * 0.15))
        }
        window.orderFrontRegardless()
        return runModal()
    }
}
