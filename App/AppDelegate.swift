import AppKit
import ReticleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var session: CaptureSession?
    private lazy var settings = SettingsWindowController(
        onHotkeyChange: { [weak self] in self?.registerHotkey($0) ?? false },
        onRecordingShortcut: { recording in
            if recording { HotkeyCenter.shared.suspendAll() } else { HotkeyCenter.shared.resumeAll() }
        })

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(
            onCapture: { [weak self] in self?.startCapture() },
            onRecognizeText: { [weak self] in self?.startCapture(mode: .recognizeText) },
            onRecord: { [weak self] in self?.startCapture(mode: .record) },
            onSettings: { [weak self] in self?.settings.show() })
        registerHotkey(.capture)
        registerHotkey(.record)
        RecordingStorage.purgeOnLaunch()
        #if DEBUG
        if ProcessInfo.processInfo.environment["RETICLE_AUTOSTART"] != nil { startCapture() }
        if ProcessInfo.processInfo.environment["RETICLE_DEBUG_PROBE"] != nil {
            Task { @MainActor in
                await Probe.run()
                exit(0)
            }
        }
        if ProcessInfo.processInfo.environment["RETICLE_E2E"] != nil {
            Task { @MainActor in
                let failures = await EndToEndTests.run()
                exit(failures == 0 ? 0 : 1)
            }
        }
        if let out = ProcessInfo.processInfo.environment["RETICLE_DEBUG_LONG"],
           let path = ProcessInfo.processInfo.environment["RETICLE_DEMO_IMAGE"],
           let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let demo = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            // Two copies stacked vertically stand in for a stitched long image.
            let ctx = CGContext(data: nil, width: demo.width, height: demo.height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(demo, in: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
            ctx.draw(demo, in: CGRect(x: 0, y: demo.height, width: demo.width, height: demo.height))
            LongImageWindow.debugRender(image: ctx.makeImage()!, scale: 2, to: URL(fileURLWithPath: out)) { NSApp.terminate(nil) }
        }
        #endif
    }

    #if DEBUG
    var debugSession: CaptureSession? { session }
    var debugHistoryMenu: HistoryMenu? { statusBar?.historyMenu }
    func debugShowSettings() { settings.show() }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        // A recording worker may still be previewing its raw file.
        if !WorkerClient.isRecording { RecordingStorage.purgeOnQuit() }
    }

    /// Returns whether registration succeeded so settings can show a conflict warning.
    @discardableResult
    func registerHotkey(_ action: HotkeyCenter.Action) -> Bool {
        let combo = Preferences.hotkey(for: action)
        let mode: CaptureMode = action == .capture ? .screenshot : .record
        let ok = HotkeyCenter.shared.register(combo, for: action) { [weak self] in self?.startCapture(mode: mode) }
        statusBar?.update(action, hotkey: combo, conflict: !ok)
        return ok
    }

    func startCapture(mode: CaptureMode = .screenshot) {
        // ⌥⇧R (or 录屏) again while recording: finish the recording.
        if mode == .record, WorkerClient.isRecording {
            WorkerClient.stopRecording()
            return
        }
        guard session == nil else { return }
        guard ScreenCapturePermission.ensureGranted() else { return }
        let s = CaptureSession(mode: mode) { [weak self] in self?.session = nil }
        session = s
        s.begin()
    }
}
