import CoreGraphics
import Foundation
@preconcurrency import Vision

/// On-device OCR with Vision.
public enum TextRecognizer {
    /// Preferred languages, in priority order; filtered by what this macOS supports.
    static let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]

    public static func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Perform synchronously and read results once, so the continuation resumes exactly once.
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let supported = (try? request.supportedRecognitionLanguages()) ?? []
                let languages = preferredLanguages.filter { supported.contains($0) }
                if !languages.isEmpty { request.recognitionLanguages = languages }
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let lines = (request.results ?? []).compactMap { o -> RecognizedLine? in
                        guard let best = o.topCandidates(1).first else { return nil }
                        let b = o.boundingBox // normalized, bottom-left origin
                        return RecognizedLine(text: best.string, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
                    }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Recognized text in reading order; empty when nothing was found.
    public static func text(in image: CGImage) async throws -> String {
        ReadingOrder.text(from: try await recognize(image))
    }
}
