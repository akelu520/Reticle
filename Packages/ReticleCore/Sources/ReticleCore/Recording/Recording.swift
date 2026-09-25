import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum RecordingFormat: String, CaseIterable, Sendable {
    case mp4, gif

    public var fileExtension: String { rawValue }
    public var utType: UTType { self == .mp4 ? .mpeg4Movie : .gif }
}

public enum RecordingLimits {
    /// Recordings stop automatically after one hour.
    public static let maxDuration: TimeInterval = 3600
    public static let gifFrameRate: Double = 10
    public static let gifMaxSide: CGFloat = 960

    /// Video encoders need even dimensions.
    public static func evenPixelSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, floor(size.width / 2) * 2), height: max(2, floor(size.height / 2) * 2))
    }
}

public enum DurationFormat {
    /// "00:07", "12:34", "1:02:03".
    public static func string(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

public enum GIFPlan {
    /// Sample times at `fps` covering `start ..< end`.
    public static func frameTimes(start: TimeInterval, end: TimeInterval, fps: Double = RecordingLimits.gifFrameRate) -> [TimeInterval] {
        guard end > start, fps > 0 else { return [] }
        let count = max(1, Int(((end - start) * fps).rounded(.up)))
        return (0..<count).map { start + Double($0) / fps }
    }

    /// Scales `size` down so its longer side is at most `maxSide`, keeping the aspect ratio.
    public static func outputSize(for size: CGSize, maxSide: CGFloat = RecordingLimits.gifMaxSide) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return size }
        let k = maxSide / longest
        return CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
    }
}

/// Streams frames into an animated GIF file without keeping them in memory.
public final class GIFWriter {
    private let destination: CGImageDestination
    private let frameProperties: CFDictionary

    public init?(url: URL, frameCount: Int, frameDelay: Double) {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { return nil }
        destination = d
        CGImageDestinationSetProperties(d, [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
        ] as CFDictionary)
        frameProperties = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: frameDelay],
        ] as CFDictionary
    }

    public func add(_ image: CGImage) {
        CGImageDestinationAddImage(destination, image, frameProperties)
    }

    public func finish() -> Bool {
        CGImageDestinationFinalize(destination)
    }
}

public enum TemporaryFiles {
    /// Deletes regular files in `directory` last modified before `date`. Returns how many were removed.
    @discardableResult
    public static func purge(in directory: URL, olderThan date: Date, fileManager: FileManager = .default) -> Int {
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return 0 }
        var removed = 0
        for url in items {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let modified = values?.contentModificationDate, modified < date else { continue }
            if (try? fileManager.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }
}
