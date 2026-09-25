import AppKit
import ReticleCore

/// Recent screenshots (最近截图). Disk work runs on a background queue; the
/// menu reads a main-thread copy of the entries and loads thumbnails only while open.
@MainActor
final class ScreenshotHistory {
    static let shared = ScreenshotHistory()

    private let queue = DispatchQueue(label: "reticle.history", qos: .utility)
    /// Touched only on `queue`.
    nonisolated(unsafe) private let store: ScreenshotHistoryStore
    private(set) var entries: [ScreenshotHistoryEntry]

    private init() {
        var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Reticle")
            .appendingPathComponent("History", isDirectory: true)
        #if DEBUG
        // E2E tests use a throwaway folder instead of the user's history.
        if let dir = ProcessInfo.processInfo.environment["RETICLE_HISTORY_DIR"] { directory = URL(fileURLWithPath: dir, isDirectory: true) }
        #endif
        store = ScreenshotHistoryStore(directory: directory)
        entries = store.entries
    }

    var directory: URL { store.directory }

    /// Adds a finished screenshot (copied, saved or pinned) unless history is turned off.
    func record(_ image: CGImage) {
        guard Preferences.historyEnabled else { return }
        queue.async { [store] in
            guard let png = ImageEncoder.png(image) else { return }
            try? store.add(png: png)
            let entries = store.entries
            DispatchQueue.main.async { MainActor.assumeIsolated { ScreenshotHistory.shared.entries = entries } }
        }
    }

    func imageURL(for entry: ScreenshotHistoryEntry) -> URL {
        queue.sync { store.imageURL(for: entry) }
    }

    func thumbnail(for entry: ScreenshotHistoryEntry) -> NSImage? {
        let url = queue.sync { store.thumbnailURL(for: entry) }
        guard let image = NSImage(contentsOf: url) else { return nil }
        // Menu rows: 80 pt wide at most, 50 pt tall at most.
        let k = min(80 / max(image.size.width, 1), 50 / max(image.size.height, 1), 1)
        image.size = CGSize(width: image.size.width * k, height: image.size.height * k)
        return image
    }

    /// 重新复制: puts the stored image back on the pasteboard.
    @discardableResult
    func copy(_ entry: ScreenshotHistoryEntry) -> Bool {
        guard let source = CGImageSourceCreateWithURL(imageURL(for: entry) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        return OutputService.copyToPasteboard(image)
    }

    func open(_ entry: ScreenshotHistoryEntry) {
        NSWorkspace.shared.open(imageURL(for: entry))
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([entries.first.map(imageURL(for:)) ?? directory])
    }

    func clear() {
        queue.async { [store] in
            try? store.clear()
            DispatchQueue.main.async { MainActor.assumeIsolated { ScreenshotHistory.shared.entries = [] } }
        }
    }

    /// Waits for queued disk work (tests).
    func flush() {
        queue.sync {}
    }
}
