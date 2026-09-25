import AppKit
import AVKit
import ReticleCore

/// After 结束录屏: play back, 剪辑 (system trim UI), then 下载 or 复制到剪贴板.
@MainActor
final class RecordingPreviewWindow: NSWindow, NSWindowDelegate {
    private static var open: [RecordingPreviewWindow] = []

    private let source: URL
    private let format: RecordingFormat
    private let playerView = AVPlayerView()
    private let status = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []

    static func show(url: URL, format: RecordingFormat) {
        let w = RecordingPreviewWindow(url: url, format: format)
        open.append(w)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private init(url: URL, format: RecordingFormat) {
        source = url
        self.format = format
        super.init(contentRect: CGRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)
        title = "录屏（\(format == .gif ? "GIF" : "MP4")）"
        isReleasedWhenClosed = false
        delegate = self
        level = .floating
        build()
        center()
        Task { await loadTitle() }
        #if DEBUG
        if ProcessInfo.processInfo.environment["RETICLE_WORKER_SELFTEST"] != nil {
            Task { @MainActor in await selfTest() }
        }
        #endif
    }

    #if DEBUG
    /// E2E: report checks on stdout as "✓ name" / "✗ name", then copy to the pasteboard and close.
    private func selfTest() async {
        func report(_ name: String, _ ok: Bool) {
            FileHandle.standardOutput.write(Data("\(ok ? "✓" : "✗") \(name)\n".utf8))
        }
        let deadline = Date().addingTimeInterval(5)
        while !playerView.canBeginTrimming, Date() < deadline { try? await Task.sleep(nanoseconds: 100_000_000) }
        report("\(format.rawValue)：预览窗口可剪辑", playerView.canBeginTrimming)
        download()
        try? await Task.sleep(nanoseconds: 800_000_000)
        report("\(format.rawValue)：下载弹出保存面板", attachedSheet != nil)
        if let sheet = attachedSheet { endSheet(sheet, returnCode: .cancel) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        copyToPasteboard()
        let copied = Date().addingTimeInterval(30)
        while status.stringValue != "已复制到剪贴板", Date() < copied { try? await Task.sleep(nanoseconds: 100_000_000) }
        report("\(format.rawValue)：复制到剪贴板", status.stringValue == "已复制到剪贴板")
        close()
    }
    #endif

    private func build() {
        guard let content = contentView else { return }
        let footerHeight: CGFloat = 48
        playerView.frame = CGRect(x: 0, y: footerHeight, width: content.bounds.width, height: content.bounds.height - footerHeight)
        playerView.autoresizingMask = [.width, .height]
        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: source)
        content.addSubview(playerView)

        status.textColor = .secondaryLabelColor
        status.frame = CGRect(x: 16, y: 15, width: 260, height: 18)
        status.autoresizingMask = [.maxXMargin]
        content.addSubview(status)

        var x = content.bounds.width - 16
        for (title, action) in [("复制到剪贴板", #selector(copyToPasteboard)), ("下载", #selector(download)), ("剪辑", #selector(trim))] {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.sizeToFit()
            b.frame.size.width = max(b.frame.width + 12, 72)
            x -= b.frame.width
            b.frame.origin = CGPoint(x: x, y: 10)
            b.autoresizingMask = [.minXMargin]
            content.addSubview(b)
            buttons.append(b)
            x -= 8
        }
    }

    private func loadTitle() async {
        guard let duration = try? await AVURLAsset(url: source).load(.duration) else { return }
        title = "录屏（\(format == .gif ? "GIF" : "MP4")） · \(DurationFormat.string(CMTimeGetSeconds(duration)))"
    }

    @objc private func trim() {
        guard playerView.canBeginTrimming else { return }
        playerView.beginTrimming { _ in }
    }

    /// The range kept by the trim UI, or the whole recording.
    private func selectedRange() async -> CMTimeRange {
        let duration = (try? await AVURLAsset(url: source).load(.duration)) ?? .zero
        guard let item = playerView.player?.currentItem else { return CMTimeRange(start: .zero, duration: duration) }
        let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : duration
        return CMTimeRange(start: start, end: end)
    }

    @objc private func download() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.directoryURL = Preferences.saveDirectory
        panel.nameFieldStringValue = FileNaming.name(for: Date(), extension: format.fileExtension)
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Preferences.saveDirectory = url.deletingLastPathComponent()
            self?.runExport(to: url) { self?.close() }
        }
    }

    @objc private func copyToPasteboard() {
        let url = RecordingStorage.clipboardDirectory.appendingPathComponent(FileNaming.name(for: Date(), extension: format.fileExtension))
        runExport(to: url) { [weak self] in
            // Copied as a file, like Finder: paste into chats, documents or folders.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])
            self?.status.stringValue = "已复制到剪贴板"
        }
    }

    private func runExport(to url: URL, then done: @escaping () -> Void) {
        setBusy(true)
        status.stringValue = format == .gif ? "正在生成 GIF…" : "正在导出…"
        let format = self.format, source = self.source
        Task { @MainActor in
            let range = await selectedRange()
            do {
                try await RecordingExporter.export(source: source, range: range, format: format, to: url)
                setBusy(false)
                status.stringValue = ""
                done()
            } catch {
                setBusy(false)
                status.stringValue = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        for b in buttons { b.isEnabled = !busy }
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        playerView.player = nil
        Self.open.removeAll { $0 === self }
        if Self.open.isEmpty {
            // Let the close finish, then leave: this is the worker's last window.
            DispatchQueue.main.async { WorkerApp.finish() }
        }
    }

}
