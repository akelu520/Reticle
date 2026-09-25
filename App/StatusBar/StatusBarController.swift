import AppKit
import ReticleCore

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let captureItem = NSMenuItem(title: "截图", action: #selector(capture), keyEquivalent: "")
    private let recordItem = NSMenuItem(title: "录屏", action: #selector(record), keyEquivalent: "")
    let historyMenu = HistoryMenu(history: .shared)
    private let onCapture: () -> Void
    private let onRecognizeText: () -> Void
    private let onRecord: () -> Void
    private let onSettings: () -> Void

    init(onCapture: @escaping () -> Void, onRecognizeText: @escaping () -> Void, onRecord: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onRecognizeText = onRecognizeText
        self.onRecord = onRecord
        self.onSettings = onSettings
        super.init()
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Reticle")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        captureItem.target = self
        menu.addItem(captureItem)
        let ocr = NSMenuItem(title: "提取文字", action: #selector(recognizeText), keyEquivalent: "")
        ocr.target = self
        menu.addItem(ocr)
        recordItem.target = self
        menu.addItem(recordItem)
        menu.addItem(.separator())
        let recent = NSMenuItem(title: "最近截图", action: nil, keyEquivalent: "")
        recent.submenu = historyMenu
        menu.addItem(recent)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "关于 Reticle", action: #selector(about), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Reticle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func update(_ action: HotkeyCenter.Action, hotkey combo: HotkeyCombo, conflict: Bool) {
        let item = action == .capture ? captureItem : recordItem
        let name = action == .capture ? "截图" : "录屏"
        item.title = conflict ? "\(name)（快捷键 \(combo.displayString) 被占用）" : name
        let key = String(combo.displayString.last ?? " ").lowercased()
        let single = combo.displayString.drop(while: { "⌃⌥⇧⌘".contains($0) }).count == 1
        item.keyEquivalent = conflict || !single ? "" : key
        var mask: NSEvent.ModifierFlags = []
        if combo.modifiers.contains(.command) { mask.insert(.command) }
        if combo.modifiers.contains(.shift) { mask.insert(.shift) }
        if combo.modifiers.contains(.option) { mask.insert(.option) }
        if combo.modifiers.contains(.control) { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
    }

    @objc private func capture() { onCapture() }
    @objc private func recognizeText() { onRecognizeText() }
    @objc private func record() { onRecord() }
    @objc private func openSettings() { onSettings() }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
