import AppKit
import ReticleCore
import ScreenCaptureKit

/// A frozen image of one display plus the window frames on it.
struct ScreenSnapshot {
    let screen: NSScreen
    let image: CGImage
    /// Window frames in screen-local flipped points, front to back.
    let windows: [CGRect]

    /// Pixels per point for this snapshot.
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
}

enum ScreenGrabber {
    enum Failure: LocalizedError {
        case noDisplays
        /// Screens exist but none matched a display ScreenCaptureKit shares.
        case displaysUnavailable(screens: [CGDirectDisplayID], shared: [CGDirectDisplayID])

        var errorDescription: String? {
            switch self {
            case .noDisplays: "没有可截取的显示器"
            case let .displaysUnavailable(screens, shared):
                "无法获取显示器画面（屏幕 \(screens)，可共享 \(shared)）。请确认已授予屏幕录制权限。"
            }
        }
    }

    /// Captures every display in parallel, excluding Reticle's own windows.
    @MainActor
    static func captureAll() async throws -> [ScreenSnapshot] {
        #if DEBUG
        if let demo = demoSnapshots() { return demo }
        #endif
        let screens = NSScreen.screens
        guard let primary = screens.first else { throw Failure.noDisplays }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApp = content.applications.filter { $0.processID == getpid() }
        let windowFrames = cgWindowFrames()

        var jobs: [(NSScreen, SCContentFilter, SCStreamConfiguration)] = []
        for screen in screens {
            guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
            config.height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            jobs.append((screen, filter, config))
        }

        if jobs.isEmpty {
            throw Failure.displaysUnavailable(screens: screens.compactMap(\.displayID), shared: content.displays.map(\.displayID))
        }

        let images = try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
            for (i, job) in jobs.enumerated() {
                let filter = job.1, config = job.2
                group.addTask { (i, try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)) }
            }
            var result: [Int: CGImage] = [:]
            for try await (i, image) in group { result[i] = image }
            return result
        }

        return jobs.enumerated().compactMap { i, job in
            guard let image = images[i] else { return nil }
            let screen = job.0
            let local = CGRect(origin: .zero, size: screen.frame.size)
            let windows = windowFrames
                .map { CoordinateSpace.localFlipped(fromCGGlobal: $0, screenFrame: screen.frame, primaryHeight: primary.frame.height) }
                .filter { $0.intersects(local) }
            return ScreenSnapshot(screen: screen, image: image, windows: windows)
        }
    }

    /// On-screen windows of other apps below the Dock level, in CG global coordinates, front to back:
    /// normal and always-on-top windows (e.g. picture-in-picture) and desktop widgets. The
    /// wallpaper covers the whole screen and comes last, so it only matches where nothing else does.
    private static func cgWindowFrames() -> [CGRect] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = getpid()
        return info.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) != pid,
                  let layer = w[kCGWindowLayer as String] as? Int, layer < Int(CGWindowLevelForKey(.dockWindow)),
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width >= 40, rect.height >= 40 else { return nil }
            return rect
        }
    }

    #if DEBUG
    /// `RETICLE_DEMO_IMAGE=/path.png` replaces the capture with a static image on
    /// the primary display (the one with the menu bar), so the overlay can be exercised
    /// without permissions. Not `NSScreen.main`: that follows focus between displays.
    @MainActor
    private static func demoSnapshots() -> [ScreenSnapshot]? {
        guard let path = ProcessInfo.processInfo.environment["RETICLE_DEMO_IMAGE"],
              let screen = NSScreen.screens.first,
              let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let s = screen.frame.size
        let demoWindows = [CGRect(x: s.width * 0.1, y: s.height * 0.1, width: s.width * 0.4, height: s.height * 0.5)]
        return [ScreenSnapshot(screen: screen, image: image, windows: demoWindows)]
    }
    #endif
}
