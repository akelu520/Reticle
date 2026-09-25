import AppKit
import ReticleCore

/// One screenshot from hotkey to copy/save/cancel. Owns every overlay window and
/// releases all images when it ends.
@MainActor
final class CaptureSession {
    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    private var previousApp: NSRunningApplication?
    private let onEnd: () -> Void
    private var ended = false
    private(set) var mode: CaptureMode

    init(mode: CaptureMode = .screenshot, onEnd: @escaping () -> Void) {
        self.mode = mode
        self.onEnd = onEnd
    }

    func begin() {
        previousApp = NSWorkspace.shared.frontmostApplication
        Task { @MainActor in
            do {
                let snapshots = try await ScreenGrabber.captureAll()
                guard !snapshots.isEmpty else { throw ScreenGrabber.Failure.noDisplays }
                present(snapshots)
            } catch {
                showError(error)
                end(restoreFocus: true)
            }
        }
    }

    private func present(_ snapshots: [ScreenSnapshot]) {
        let mouse = NSEvent.mouseLocation
        var keyWindow: OverlayWindow?
        for snap in snapshots {
            let window = OverlayWindow(screen: snap.screen)
            let view = OverlayView(snapshot: snap, session: self)
            window.contentView = view
            windows.append(window)
            views.append(view)
            if snap.screen.frame.contains(mouse) { keyWindow = window }
        }
        NSApp.activate(ignoringOtherApps: true)
        for w in windows { w.orderFrontRegardless() }
        (keyWindow ?? windows.first)?.makeKeyAndOrderFront(nil)
        for v in views { v.refreshHover() }
        #if DEBUG
        if let out = ProcessInfo.processInfo.environment["RETICLE_DEBUG_RENDER"], let v = views.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let b = v.bounds
                v.debugRender(selection: nil, cursor: CGPoint(x: b.width * 0.3, y: b.height * 0.3),
                              to: URL(fileURLWithPath: out + "-hover.png"))
                v.debugRender(selection: CGRect(x: b.width * 0.25, y: b.height * 0.2, width: b.width * 0.4, height: b.height * 0.35),
                              cursor: CGPoint(x: b.width * 0.65, y: b.height * 0.55),
                              to: URL(fileURLWithPath: out + "-selected.png"))
                if let img = v.exportImage(), let data = ImageEncoder.png(img) {
                    try? data.write(to: URL(fileURLWithPath: out + "-export.png"))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    v.debugRender(selection: CGRect(x: b.width * 0.25, y: b.height * 0.2, width: b.width * 0.4, height: b.height * 0.35),
                                  cursor: CGPoint(x: b.width * 0.65, y: b.height * 0.55),
                                  to: URL(fileURLWithPath: out + "-selected2.png"))
                    v.debugRender(selection: CGRect(x: b.width * 0.25, y: b.height * 0.2, width: b.width * 0.4, height: b.height * 0.35),
                                  cursor: .zero, annotate: true, to: URL(fileURLWithPath: out + "-annotated.png"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        v.debugRender(selection: CGRect(x: b.width * 0.25, y: b.height * 0.2, width: b.width * 0.4, height: b.height * 0.35),
                                      cursor: .zero, to: URL(fileURLWithPath: out + "-annotated2.png"))
                        if let img = v.exportImage(), let data = ImageEncoder.png(img) {
                            try? data.write(to: URL(fileURLWithPath: out + "-annotated-export.png"))
                        }
                        v.debugStartRecognition()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            v.debugRender(selection: CGRect(x: b.width * 0.25, y: b.height * 0.2, width: b.width * 0.4, height: b.height * 0.35),
                                          cursor: .zero, to: URL(fileURLWithPath: out + "-ocr.png"))
                            self.setMode(.record)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                v.debugRender(selection: CGRect(x: b.width * 0.25, y: b.height * 0.2, width: b.width * 0.4, height: b.height * 0.35),
                                              cursor: .zero, to: URL(fileURLWithPath: out + "-record.png"))
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
            }
        }
        #endif
    }

    // MARK: - Called by overlay views

    /// Only one display can hold the selection; others fall back to a plain dim.
    func selectionStarted(in view: OverlayView) {
        for v in views where v !== view { v.deactivate() }
        view.window?.makeKey()
    }

    func selectionCleared() {
        for v in views { v.reactivate() }
    }

    func setMode(_ mode: CaptureMode) {
        self.mode = mode
        for v in views { v.modeChanged() }
    }

    /// 固定到屏幕: float the result where the selection was, then end the session.
    func pin(from view: OverlayView) {
        guard let image = view.exportImage(), let frame = view.selectionGlobalFrame else { return }
        PinManager.shared.pin(image, frame: frame, scale: view.window?.backingScaleFactor ?? 2)
        ScreenshotHistory.shared.record(image)
        end(restoreFocus: true)
    }

    /// 开始滚动截图: close the frozen overlay and stream the live region instead.
    func startScrollCapture(from view: OverlayView) {
        guard let rect = view.selection else { return }
        let screen = view.snapshot.screen
        let scale = view.snapshot.scale
        end(restoreFocus: true)
        ScrollCaptureController.start(screen: screen, rect: rect, scale: scale)
    }

    /// 开始录制: close the overlay and record the live region.
    func startRecording(from view: OverlayView, format: RecordingFormat) {
        guard let rect = view.selection, let displayID = view.snapshot.screen.displayID else { return }
        let request = WorkerProtocol.RecordRequest(displayID: displayID, rect: rect, scale: view.snapshot.scale, format: format.rawValue)
        end(restoreFocus: true)
        do {
            try WorkerClient.startRecording(request)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法开始录屏"
            alert.runModal()
        }
    }

    /// A link in recognized text: leave the capture so the browser is visible.
    func open(_ url: URL) {
        end(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    func cancel() {
        end(restoreFocus: true)
    }

    func copy(from view: OverlayView) {
        guard let image = view.exportImage() else { return }
        if OutputService.copyToPasteboard(image) {
            ScreenshotHistory.shared.record(image)
            end(restoreFocus: true)
        } else {
            showError(OutputService.Failure.encode)
        }
    }

    func save(from view: OverlayView) {
        guard let image = view.exportImage() else { return }
        #if DEBUG
        // E2E tests cannot drive a modal save panel; write straight to this folder instead.
        if let dir = ProcessInfo.processInfo.environment["RETICLE_E2E_SAVE_DIR"] {
            try? OutputService.write(image, to: URL(fileURLWithPath: dir).appendingPathComponent(FileNaming.screenshotName(for: Date())))
            ScreenshotHistory.shared.record(image)
            end(restoreFocus: true)
            return
        }
        #endif
        for w in windows { w.orderOut(nil) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = Preferences.saveDirectory
        panel.nameFieldStringValue = FileNaming.screenshotName(for: Date())
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try OutputService.write(image, to: url)
                Preferences.saveDirectory = url.deletingLastPathComponent()
                ScreenshotHistory.shared.record(image)
                end(restoreFocus: true)
                return
            } catch {
                showError(error)
            }
        }
        // Cancelled or failed: bring the session back so the user can retry.
        for w in windows { w.orderFrontRegardless() }
        view.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Teardown

    private func end(restoreFocus: Bool) {
        guard !ended else { return }
        ended = true
        for w in windows {
            w.orderOut(nil)
            w.contentView = nil
        }
        windows.removeAll()
        views.removeAll()
        if restoreFocus { previousApp?.activate() }
        onEnd()
    }

    private func showError(_ error: Error) {
        for w in windows { w.orderOut(nil) }
        let alert = NSAlert()
        alert.messageText = "截图失败"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
