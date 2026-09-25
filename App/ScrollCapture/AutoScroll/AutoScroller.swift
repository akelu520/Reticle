#if !APPSTORE
import AppKit
import ApplicationServices

/// 自动滚动: posts scroll-wheel events at the region's center. Needs the
/// Accessibility permission (it controls the computer), so it is
/// isolated here and compiled out for a sandboxed App Store build.
@MainActor
final class AutoScroller {
    private var timer: Timer?
    private let point: CGPoint
    /// Pixels per tick; 20 ticks/s ≈ 600 px/s, slow enough for 15 fps stitching.
    private static let step: Int32 = 30

    /// - Parameter point: where to scroll, in CG global coordinates (top-left origin).
    init(point: CGPoint) {
        self.point = point
    }

    var isRunning: Bool { timer != nil }

    /// Returns false (after showing the system prompt) when the permission is missing.
    static func ensurePermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard timer == nil else { return }
        // Scroll events go to the window under the cursor, so move it into the region first.
        CGWarpMouseCursorPosition(point)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [point] _ in
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -Self.step, wheel2: 0, wheel3: 0)
            event?.location = point
            event?.post(tap: .cghidEventTap)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
