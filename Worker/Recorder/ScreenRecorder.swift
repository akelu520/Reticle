import AppKit
import ReticleCore
import ScreenCaptureKit

/// Records one region: red dashed border (click-through), a small control with
/// the elapsed time and 结束录屏, auto-stop at one hour, then the preview window.
@MainActor
final class ScreenRecorder: NSObject, SCStreamDelegate {
    private static var current: ScreenRecorder?

    private let screen: NSScreen
    private let rect: CGRect
    private let scale: CGFloat
    private let format: RecordingFormat
    private var stream: SCStream?
    private var sink: RecordingSink?
    private var frameWindow: NSWindow?
    private var controls: RecordingControlPanel?
    private var timer: Timer?
    private var startDate = Date()
    private var stopping = false

    static func start(screen: NSScreen, rect: CGRect, scale: CGFloat, format: RecordingFormat) {
        guard current == nil else { return }
        let r = ScreenRecorder(screen: screen, rect: rect, scale: scale, format: format)
        current = r
        r.begin()
    }

    static func stopCurrent() {
        current?.stop()
    }

    private init(screen: NSScreen, rect: CGRect, scale: CGFloat, format: RecordingFormat) {
        self.screen = screen
        self.rect = rect
        self.scale = scale
        self.format = format
    }

    private func begin() {
        showWindows()
        Task { @MainActor in
            do {
                try await startStream()
                startDate = Date()
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                #if DEBUG
                // E2E tests: stop by themselves after N seconds.
                if let s = ProcessInfo.processInfo.environment["RETICLE_WORKER_AUTOSTOP"].flatMap(Double.init) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in self?.stop() }
                }
                #endif
            } catch {
                tearDown()
                WorkerApp.fail("无法开始录屏：\(error.localizedDescription)")
            }
        }
    }

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
        frame.contentView = RecordingBorderView(region: rect)
        frame.orderFrontRegardless()
        frameWindow = frame

        let panel = RecordingControlPanel { [weak self] in self?.stop() }
        let size = panel.frame.size
        let global = CoordinateSpace.appKitGlobal(fromLocalFlipped: rect, screenFrame: screen.frame)
        var origin = CGPoint(x: global.maxX - size.width, y: global.minY - 8 - size.height)
        if origin.y < screen.frame.minY { origin.y = global.maxY + 8 }
        if origin.y + size.height > screen.frame.maxY { origin.y = global.minY + 8 }
        origin.x = min(max(origin.x, screen.frame.minX), screen.frame.maxX - size.width)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        controls = panel
    }

    private func startStream() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else {
            throw RecordingError.noDisplay
        }
        let own = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let pixelSize = RecordingLimits.evenPixelSize(CGSize(width: rect.width * scale, height: rect.height * scale))
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int(pixelSize.width)
        config.height = Int(pixelSize.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        let sink = try RecordingSink(url: RecordingStorage.newRawURL(), pixelSize: pixelSize)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        self.sink = sink
        self.stream = stream
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.stop() }
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(startDate)
        controls?.setElapsed(elapsed)
        if elapsed >= RecordingLimits.maxDuration { stop() }
    }

    private func stop() {
        guard !stopping else { return }
        stopping = true
        timer?.invalidate()
        let format = self.format
        Task { @MainActor in
            try? await stream?.stopCapture()
            guard let sink else {
                tearDown()
                return
            }
            let result: Result<URL, Error> = await withCheckedContinuation { continuation in
                sink.finish { continuation.resume(returning: $0) }
            }
            tearDown()
            switch result {
            case let .success(url):
                RecordingPreviewWindow.show(url: url, format: format)
            case let .failure(error):
                WorkerApp.fail(error.localizedDescription)
            }
        }
    }

    private func tearDown() {
        timer?.invalidate()
        frameWindow?.orderOut(nil)
        controls?.orderOut(nil)
        frameWindow = nil
        controls = nil
        stream = nil
        sink = nil
        Self.current = nil
    }
}

private final class RecordingBorderView: NSView {
    private let region: CGRect

    init(region: CGRect) {
        self.region = region
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(rect: region.insetBy(dx: -1.5, dy: -1.5))
        border.lineWidth = 2
        border.setLineDash([6, 4], count: 2, phase: 0)
        NSColor(srgbRed: 0xF5 / 255, green: 0x4A / 255, blue: 0x45 / 255, alpha: 1).setStroke()
        border.stroke()
    }
}

/// "● 00:12  结束录屏"
final class RecordingControlPanel: NSPanel {
    private let time = NSTextField(labelWithString: "00:00")
    private let onStop: () -> Void

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
        let size = CGSize(width: 170, height: 40)
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let root = NSView(frame: CGRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        root.layer?.cornerRadius = 8
        root.appearance = NSAppearance(named: .aqua)
        contentView = root

        let dot = NSView(frame: CGRect(x: 12, y: 16, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(srgbRed: 0xF5 / 255, green: 0x4A / 255, blue: 0x45 / 255, alpha: 1).cgColor
        dot.layer?.cornerRadius = 4
        root.addSubview(dot)
        time.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        time.frame = CGRect(x: 26, y: 11, width: 60, height: 18)
        root.addSubview(time)
        let stop = NSButton(title: "结束录屏", target: self, action: #selector(stopTapped))
        stop.bezelStyle = .rounded
        stop.frame = CGRect(x: 84, y: 6, width: 80, height: 28)
        root.addSubview(stop)
    }

    func setElapsed(_ seconds: TimeInterval) {
        time.stringValue = DurationFormat.string(seconds)
    }

    @objc private func stopTapped() { onStop() }
}
