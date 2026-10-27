import CoreMedia
import ReticleCore
import ScreenCaptureKit
import VideoToolbox

/// Receives SCStream frames on a background queue and feeds the stitcher, which follows the
/// page whichever way it scrolls (down, up, or sideways). All stitcher access happens on `queue`.
final class ScrollFrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Progress: Sendable {
        var update: ScrollStitcher.Update
        /// Pixels along the scroll direction.
        var length: Int
        /// Nil until the direction is clear.
        var axis: ScrollAxis?
        var preview: CGImage?
    }

    let queue = DispatchQueue(label: "reticle.scroll-capture", qos: .userInitiated)
    private let stitcher = ScrollCaptureStitcher()
    /// Preview box in pixels.
    private let previewSize: CGSize
    private var lastPreview = Date.distantPast
    private let onProgress: @Sendable (Progress) -> Void

    init(previewSize: CGSize, onProgress: @escaping @Sendable (Progress) -> Void) {
        self.previewSize = previewSize
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
            preview = makePreview(frame: image)
            lastPreview = Date()
        } else if update == .started {
            preview = makePreview(frame: image)
        }
        onProgress(Progress(update: update, length: stitcher.length, axis: stitcher.axis, preview: preview))
    }

    /// Downscaled long image for the control panel. Scrolling sideways, the strip is as tall as the
    /// box and only its newest (rightmost) part that fits is shown.
    private func makePreview(frame: CGImage) -> CGImage? {
        guard stitcher.axis == .horizontal else { return stitcher.compose(scale: previewSize.width / CGFloat(frame.width)) }
        guard let strip = stitcher.compose(scale: previewSize.height / CGFloat(frame.height)) else { return nil }
        let w = min(strip.width, Int(previewSize.width))
        return strip.cropping(to: CGRect(x: strip.width - w, y: 0, width: w, height: strip.height))
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
