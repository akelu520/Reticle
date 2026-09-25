import CoreGraphics
import Foundation

/// Contract between Reticle and ReticleWorker, the helper process that runs
/// memory-heavy features (Vision OCR, recording with AVFoundation) so their
/// frameworks never stay resident in the menu-bar app. The worker is launched
/// per task and exits when done.
enum WorkerProtocol {
    static let executableName = "ReticleWorker"

    enum Command: String {
        /// `ocr <png path>` → one `OCRResponse` JSON line on stdout.
        case ocr
        /// `record <RecordRequest JSON>` → recording UI, preview, export; exits when the preview closes.
        case record
        /// `preview <mp4 path> <mp4|gif>` → preview window only (tests and re-opening a raw recording).
        case preview
    }

    struct OCRResponse: Codable {
        var text: String?
        var error: String?
    }

    struct RecordRequest: Codable {
        var displayID: UInt32
        /// Region in screen-local flipped points.
        var rect: CGRect
        var scale: CGFloat
        var format: String
    }

    /// Sent by the app to a recording worker to stop (⌥⇧R pressed again).
    static let stopSignal = SIGUSR1
}
