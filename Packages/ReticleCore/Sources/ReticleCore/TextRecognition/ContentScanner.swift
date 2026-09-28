import CoreGraphics
import Foundation
@preconcurrency import Vision

/// Quick look at a selection: whether it contains text, and the payloads of any QR codes.
/// Drives which of 提取文字 / 识别二维码 are offered.
public struct ScanResult: Codable, Equatable, Sendable {
    public var hasText: Bool
    public var codes: [String]

    public init(hasText: Bool, codes: [String]) {
        self.hasText = hasText
        self.codes = codes
    }
}

public enum ContentScanner {
    public static func scan(_ image: CGImage) async throws -> ScanResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Rectangle detection is much cheaper than recognition and enough to decide.
                let text = VNDetectTextRectanglesRequest()
                let barcodes = VNDetectBarcodesRequest()
                barcodes.symbologies = [.qr, .microQR]
                do {
                    try VNImageRequestHandler(cgImage: image).perform([text, barcodes])
                    var codes: [String] = []
                    for payload in (barcodes.results ?? []).compactMap(\.payloadStringValue) where !codes.contains(payload) {
                        codes.append(payload)
                    }
                    continuation.resume(returning: ScanResult(hasText: !(text.results ?? []).isEmpty, codes: codes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
