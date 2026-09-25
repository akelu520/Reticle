import CoreMedia
import ReticleCore
import ScreenCaptureKit
import VideoToolbox

/// Receives SCStream frames on a background queue and feeds the stitcher.
/// All stitcher access happens on `queue`.
final class ScrollFrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Progress: Sendable {
        var update: ScrollStitcher.Update
        var height: Int
        var preview: CGImage?
    }

    let queue = DispatchQueue(label: "reticle.scroll-capture", qos: .userInitiated)
    private let stitcher = ScrollStitcher()
    private let previewWidth: CGFloat
    private var lastPreview = Date.distantPast
    private let onProgress: @Sendable (Progress) -> Void

    init(previewWidth: CGFloat, onProgress: @escaping @Sendable (Progress) -> Void) {
        self.previewWidth = previewWidth
        self.onProgress = onProgress
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard let image else { return }
        let update = stitcher.add(image)
        var preview: CGImage?
        // Recomposing the preview is the costly part; limit it to ~3 per second.
        if case .moved = update, Date().timeIntervalSince(lastPreview) > 0.33 {
            preview = stitcher.compose(scale: previewWidth / CGFloat(image.width))
            lastPreview = Date()
        } else if update == .started {
            preview = stitcher.compose(scale: previewWidth / CGFloat(image.width))
        }
        onProgress(Progress(update: update, height: stitcher.height, preview: preview))
    }

    /// Final full-resolution image. Call on `queue`.
    func compose() -> CGImage? {
        stitcher.compose()
    }

    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
