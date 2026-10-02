#if DEBUG
import AppKit
import ScreenCaptureKit

/// `RETICLE_DEBUG_PROBE=1`: prints permission state, tries one online translation and one real capture.
@MainActor
enum Probe {
    static func run() async {
        print("屏幕录制权限 CGPreflightScreenCaptureAccess = \(CGPreflightScreenCaptureAccess())")
        print("辅助功能权限 AXIsProcessTrusted = \(AXIsProcessTrusted())")
        do {
            print("在线翻译 Hello world → \(try await OnlineTranslator.shared.translate("Hello world", to: "zh-Hans"))")
        } catch {
            print("在线翻译失败：\(error.localizedDescription)")
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("SCShareableContent：\(content.displays.count) 个显示器，\(content.windows.count) 个窗口")
            if let display = content.displays.first {
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
                print("真实截屏成功：\(image.width)×\(image.height)")
            }
        } catch {
            print("真实截屏失败：\(error.localizedDescription)")
        }
    }
}
#endif
