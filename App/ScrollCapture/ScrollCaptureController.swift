import AppKit
import ReticleCore
import ScreenCaptureKit

/// Runs one 滚动截图: shows the region border (click-through, so the page below
/// can be scrolled), streams the region, stitches frames, and hands the long
/// image to `LongImageWindow` when finished.
@MainActor
final class ScrollCaptureController: NSObject, SCStreamDelegate {
    /// The capture in progress; kept alive here after the capture session ends.
    private static var current: ScrollCaptureController?

    private let screen: NSScreen
    /// Region in screen-local flipped points.
    private let rect: CGRect
    private let scale: CGFloat
    private var stream: SCStream?
    private var sink: ScrollFrameSink?
    private var frameWindow: NSWindow?
    private var controls: ScrollControlPanel?
    private var lastMove = Date()
    private var finished = false
    #if !APPSTORE
    private var autoScroller: AutoScroller?
    private var autoStopTimer: Timer?
    #endif

    static func start(screen: NSScreen, rect: CGRect, scale: CGFloat) {
        let c = ScrollCaptureController(screen: screen, rect: rect, scale: scale)
        current = c
        c.begin()
    }

    private init(screen: NSScreen, rect: CGRect, scale: CGFloat) {
        self.screen = screen
        self.rect = rect
        self.scale = scale
    }

    private func begin() {
        showWindows()
        Task { @MainActor in
            do {
                try await startStream()
            } catch {
                controls?.setStatus("无法开始滚动截图：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Windows

    private func showWindows() {
        let frame = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        frame.setFrame(screen.frame, display: false)
        frame.level = .screenSaver
        frame.isOpaque = false
        frame.backgroundColor = .clear
        frame.hasShadow = false
        frame.ignoresMouseEvents = true
        frame.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        frame.isReleasedWhenClosed = false
        frame.contentView = RegionFrameView(region: rect)
        frame.orderFrontRegardless()
        frameWindow = frame

        let panel = ScrollControlPanel(actions: .init(
            toggleAutoScroll: { [weak self] in self?.toggleAutoScroll() },
            finish: { [weak self] in self?.finish() },
            cancel: { [weak self] in self?.cancel() }))
        let size = panel.frame.size
        let global = CoordinateSpace.appKitGlobal(fromLocalFlipped: rect, screenFrame: screen.frame)
        var origin = CGPoint(x: global.maxX + 8, y: global.maxY - size.height)
        if origin.x + size.width > screen.frame.maxX { origin.x = global.minX - 8 - size.width }
        if origin.x < screen.frame.minX { origin.x = global.maxX - size.width - 8 }
        origin.y = min(max(origin.y, screen.frame.minY), screen.frame.maxY - size.height)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        controls = panel
        #if APPSTORE
        panel.hideAutoScroll()
        #endif
    }

    // MARK: - Stream

    private func startStream() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else {
            throw ScreenGrabber.Failure.noDisplays
        }
        let own = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int((rect.width * scale).rounded())
        config.height = Int((rect.height * scale).rounded())
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        config.showsCursor = false
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        let sink = ScrollFrameSink(previewWidth: ScrollControlPanel.previewWidth * 2) { [weak self] progress in
            DispatchQueue.main.async { self?.handle(progress) }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        self.sink = sink
        self.stream = stream
        controls?.setStatus("请缓慢滚动页面，或点击“自动滚动”")
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.controls?.setStatus("滚动截图已中断：\(error.localizedDescription)") }
    }

    private func handle(_ p: ScrollFrameSink.Progress) {
        guard !finished else { return }
        if let preview = p.preview { controls?.setPreview(preview, scale: scale) }
        switch p.update {
        case .started:
            lastMove = Date()
        case .moved:
            lastMove = Date()
            controls?.setStatus("已拼接 \(p.height) 像素")
        case .unchanged:
            break
        case .mismatch:
            controls?.setStatus("滚动太快，请慢一点")
        case .limitReached:
            controls?.setStatus("已达到最大长度")
            finish()
        }
    }

    // MARK: - Auto scroll

    private func toggleAutoScroll() {
        #if !APPSTORE
        if let scroller = autoScroller, scroller.isRunning {
            stopAutoScroll()
            return
        }
        guard AutoScroller.ensurePermission() else {
            controls?.setStatus("请在“系统设置 › 隐私与安全性 › 辅助功能”中允许 Reticle，然后再试")
            return
        }
        let global = CoordinateSpace.appKitGlobal(fromLocalFlipped: rect, screenFrame: screen.frame)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let center = CGPoint(x: global.midX, y: primaryHeight - global.midY)
        let scroller = AutoScroller(point: center)
        autoScroller = scroller
        lastMove = Date()
        scroller.start()
        controls?.setAutoScrolling(true)
        // Stop once the content has not moved for a while (reached the bottom).
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastMove) > 1.2 else { return }
                self.stopAutoScroll()
                self.controls?.setStatus("已滚动到底部，点击“完成”")
            }
        }
        #endif
    }

    private func stopAutoScroll() {
        #if !APPSTORE
        autoScroller?.stop()
        autoScroller = nil
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        controls?.setAutoScrolling(false)
        #endif
    }

    // MARK: - End

    private func finish() {
        guard !finished else { return }
        finished = true
        stopAutoScroll()
        let sink = self.sink
        Task { @MainActor in
            try? await stream?.stopCapture()
            let image: CGImage? = await withCheckedContinuation { continuation in
                guard let sink else { return continuation.resume(returning: nil) }
                sink.queue.async { continuation.resume(returning: sink.compose()) }
            }
            tearDown()
            if let image {
                LongImageWindow.show(image: image, scale: scale)
            }
        }
    }

    private func cancel() {
        finished = true
        stopAutoScroll()
        Task { @MainActor in
            try? await stream?.stopCapture()
            tearDown()
        }
    }

    private func tearDown() {
        frameWindow?.orderOut(nil)
        controls?.orderOut(nil)
        frameWindow = nil
        controls = nil
        stream = nil
        sink = nil
        Self.current = nil
    }
}

/// Dims everything outside the region and outlines it; ignores the mouse.
private final class RegionFrameView: NSView {
    private let region: CGRect

    init(region: CGRect) {
        self.region = region
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: region))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.3).setFill()
        dim.fill()
        let border = NSBezierPath(rect: region.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        Palette.accent.setStroke()
        border.stroke()
    }
}
