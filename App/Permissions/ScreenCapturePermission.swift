import AppKit
import CoreGraphics

enum ScreenCapturePermission {
    private static let askedKey = "askedScreenCapture"

    /// Returns true when capturing is allowed. The first time, macOS shows its own
    /// prompt; after that, a guide explains where to enable it and offers a reset
    /// for the common "switch is on but still refused" case.
    @MainActor
    static func ensureGranted() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RETICLE_DEMO_IMAGE"] != nil { return true }
        #endif
        if CGPreflightScreenCaptureAccess() { return true }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: askedKey) {
            defaults.set(true, forKey: askedKey)
            CGRequestScreenCaptureAccess() // shows the system prompt once
            return false
        }
        let alert = NSAlert()
        alert.messageText = "需要“屏幕录制”权限"
        alert.informativeText = """
            Reticle 需要读取屏幕内容才能截图。请在“系统设置 › 隐私与安全性 › 屏幕与系统录音”中打开 Reticle，然后重新打开 Reticle。

            如果列表里 Reticle 已经是打开状态仍看到这个提示（常见于更新版本之后），是系统还记着旧版本的授权。请点“重置权限”，再按系统提示重新打开开关。
            """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "重置权限")
        alert.addButton(withTitle: "稍后")
        switch alert.runVisibly() {
        case .alertFirstButtonReturn:
            openSettings()
        case .alertSecondButtonReturn:
            reset()
        default:
            break
        }
        return false
    }

    /// Drops the stale record for this app, then asks again so the system prompt reappears.
    @MainActor
    static func reset() {
        let tccutil = Process()
        tccutil.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tccutil.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "io.github.akelu520.reticle"]
        try? tccutil.run()
        tccutil.waitUntilExit()
        CGRequestScreenCaptureAccess()
        openSettings()
    }

    private static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
