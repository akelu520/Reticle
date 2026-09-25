import AppKit
import SwiftUI

/// Created lazily on first open so SwiftUI costs nothing while idle.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let onHotkeyChange: (HotkeyCenter.Action) -> Bool
    private let onRecordingShortcut: (Bool) -> Void

    init(onHotkeyChange: @escaping (HotkeyCenter.Action) -> Bool, onRecordingShortcut: @escaping (Bool) -> Void) {
        self.onHotkeyChange = onHotkeyChange
        self.onRecordingShortcut = onRecordingShortcut
    }

    func show() {
        if window == nil {
            let view = SettingsView(onHotkeyChange: onHotkeyChange, onRecordingShortcut: onRecordingShortcut)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Reticle 设置"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
