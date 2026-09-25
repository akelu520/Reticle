import AppKit
import CoreGraphics

enum ScreenCapturePermission {
    /// Returns true when capturing is allowed. Otherwise triggers the system
    /// prompt (first time only) and shows a guide pointing to System Settings.
    @MainActor
    static func ensureGranted() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RETICLE_DEMO_IMAGE"] != nil { return true }
        #endif
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要“屏幕录制”权限"
        alert.informativeText = "Reticle 需要读取屏幕内容才能截图。请在“系统设置 › 隐私与安全性 › 屏幕与系统录音”中打开 Reticle，然后重新启动 Reticle。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
