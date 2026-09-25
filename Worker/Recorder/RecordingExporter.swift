import AVFoundation
import ReticleCore

/// Exports a trimmed range of a raw recording as MP4 (passthrough, no re-encode)
/// or as GIF (10 fps, longest side ≤ 960 px).
enum RecordingExporter {
    static func export(source: URL, range: CMTimeRange, format: RecordingFormat, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        switch format {
        case .mp4:
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw RecordingError.exportFailed
            }
            session.outputURL = destination
            session.outputFileType = .mp4
            session.timeRange = range
            await session.export()
            guard session.status == .completed else { throw session.error ?? RecordingError.exportFailed }
        case .gif:
            try await exportGIF(asset: asset, range: range, to: destination)
        }
    }

    private static func exportGIF(asset: AVURLAsset, range: CMTimeRange, to destination: URL) async throws {
        let start = CMTimeGetSeconds(range.start), end = CMTimeGetSeconds(range.end)
        let times = GIFPlan.frameTimes(start: start, end: end)
        guard !times.isEmpty, let writer = GIFWriter(url: destination, frameCount: times.count, frameDelay: 1 / RecordingLimits.gifFrameRate) else {
            throw RecordingError.exportFailed
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let natural = try await track.load(.naturalSize)
            generator.maximumSize = GIFPlan.outputSize(for: natural)
        }
        let tolerance = CMTime(seconds: 0.5 / RecordingLimits.gifFrameRate, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        for t in times {
            let (image, _) = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600))
            writer.add(image)
        }
        guard writer.finish() else { throw RecordingError.exportFailed }
    }
}
