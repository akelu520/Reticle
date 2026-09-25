import AppKit
import ReticleCore

/// "最近截图" submenu. Rows are built when the menu opens and dropped when it
/// closes, so thumbnails never stay in memory. Click = copy again; ⌥-click = open in Preview.
@MainActor
final class HistoryMenu: NSMenu, NSMenuDelegate {
    private let history: ScreenshotHistory

    init(history: ScreenshotHistory) {
        self.history = history
        super.init(title: "最近截图")
        delegate = self
        // A placeholder keeps the submenu arrow before the first open.
        addItem(NSMenuItem(title: "暂无截图", action: nil, keyEquivalent: ""))
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        let entries = history.entries
        if entries.isEmpty {
            let empty = NSMenuItem(title: Preferences.historyEnabled ? "暂无截图" : "截图历史已关闭（可在设置中打开）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            addItem(empty)
        }
        for entry in entries {
            let title = "\(Self.format(entry.date)) · \(entry.pixelWidth) × \(entry.pixelHeight)"
            let copy = NSMenuItem(title: title, action: #selector(copyEntry(_:)), keyEquivalent: "")
            copy.target = self
            copy.representedObject = entry.id
            copy.image = history.thumbnail(for: entry)
            copy.toolTip = "点击复制，按住 ⌥ 点击用预览打开"
            addItem(copy)
            let open = NSMenuItem(title: "用预览打开  \(title)", action: #selector(openEntry(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = entry.id
            open.image = copy.image
            open.isAlternate = true
            open.keyEquivalentModifierMask = .option
            addItem(open)
        }
        addItem(.separator())
        let reveal = NSMenuItem(title: "在访达中显示", action: #selector(reveal), keyEquivalent: "")
        reveal.target = self
        addItem(reveal)
        let clear = NSMenuItem(title: "清空历史…", action: #selector(confirmClear), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !entries.isEmpty
        addItem(clear)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Release thumbnails; rebuilt on next open.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.removeAllItems()
            self.addItem(NSMenuItem(title: "暂无截图", action: nil, keyEquivalent: ""))
        }
    }

    private func entry(for item: NSMenuItem) -> ScreenshotHistoryEntry? {
        guard let id = item.representedObject as? UUID else { return nil }
        return history.entries.first { $0.id == id }
    }

    @objc func copyEntry(_ item: NSMenuItem) {
        if let e = entry(for: item) { history.copy(e) }
    }

    @objc func openEntry(_ item: NSMenuItem) {
        if let e = entry(for: item) { history.open(e) }
    }

    @objc private func reveal() {
        history.revealInFinder()
    }

    @objc private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "清空截图历史？"
        alert.informativeText = "将删除最近 \(history.entries.count) 张截图的本地副本，已复制或保存的图片不受影响。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { history.clear() }
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm:ss" : "M月d日 HH:mm"
        return f.string(from: date)
    }
}
