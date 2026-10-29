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
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let cmds = env["RETICLE_REMOTE_CMDS"], let out = env["RETICLE_REMOTE_OUT"] {
            RemoteControl.run(commands: URL(fileURLWithPath: cmds), out: URL(fileURLWithPath: out))
            return
        }
        #endif
        statusBar = StatusBarController(
            onCapture: { [weak self] in self?.startCapture() },
            onRecognizeText: { [weak self] in self?.startCapture(mode: .recognizeText) },
            onRecord: { [weak self] in self?.startCapture(mode: .record) },
            onSettings: { [weak self] in self?.settings.show() })
        // Test runs launch extra copies on purpose: they leave the user's own copy and
        // its shortcuts alone, or a ⇧⌘A during a test would open two overlays.
        if !Self.isTestRun {
            quitOtherInstances()
            registerHotkey(.capture)
            registerHotkey(.record)
        }
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

    /// Every running copy receives each global shortcut, so with two copies open (an old
    /// version still running when a new one is opened from the DMG, say) one ⇧⌘A opened
    /// two capture overlays and the second showed up after the first was done.
    /// The copy opened last takes over.
    private func quitOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0 != .current }
        for app in others { app.terminate() }
        // One stuck in a modal panel may not quit on request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for app in others where !app.isTerminated { app.forceTerminate() }
        }
    }

    private static var isTestRun: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RETICLE_") }
        #else
        false
        #endif
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
