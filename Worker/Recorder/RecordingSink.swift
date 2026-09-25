import AVFoundation
import ReticleCore
import ScreenCaptureKit

/// Writes SCStream frames to an H.264 MP4 on a background queue.
final class RecordingSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "reticle.recording", qos: .userInitiated)
    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var lastTime = CMTime.invalid

    init(url: URL, pixelSize: CGSize) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let w = Int(pixelSize.width), h = Int(pixelSize.height)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                // ~0.15 bits per pixel per frame at 30 fps keeps text sharp at modest size.
                AVVideoAverageBitRateKey: max(Double(w * h) * 30 * 0.15, 2_000_000),
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer) else { return }
        let time = sampleBuffer.presentationTimeStamp
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: time)
            started = true
        }
        if input.isReadyForMoreMediaData, input.append(sampleBuffer) {
            lastTime = time
        }
    }

    /// Finishes the file. ScreenCaptureKit only delivers frames when the screen
    /// changes, so the session is extended to "now" to keep a still ending.
    func finish(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            guard started else {
                writer.cancelWriting()
                completion(.failure(RecordingError.noFrames))
                return
            }
            input.markAsFinished()
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            let gap = CMTimeGetSeconds(CMTimeSubtract(now, lastTime))
            writer.endSession(atSourceTime: gap > 0 && gap < RecordingLimits.maxDuration ? now : lastTime)
            writer.finishWriting { [self] in
                if writer.status == .completed {
                    completion(.success(url))
                } else {
                    completion(.failure(writer.error ?? RecordingError.noFrames))
                }
            }
        }
    }

    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}

enum RecordingError: LocalizedError {
    case noFrames
    case exportFailed
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "找不到要录制的显示器。"
        case .noFrames: return "没有录到任何画面。"
        case .exportFailed: return "导出失败。"
        }
    }
}
