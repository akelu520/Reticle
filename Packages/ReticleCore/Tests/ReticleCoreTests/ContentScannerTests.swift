import CoreImage
import XCTest
@testable import ReticleCore

final class ContentScannerTests: XCTestCase {
    private func qrImage(_ payload: String) -> CGImage {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        // A quiet zone around the code, as on screen.
        let padded = scaled.transformed(by: CGAffineTransform(translationX: 40, y: 40))
            .composited(over: CIImage(color: .white).cropped(to: scaled.extent.insetBy(dx: -40, dy: -40).offsetBy(dx: 40, dy: 40)))
        return CIContext().createCGImage(padded, from: padded.extent)!
    }

    private func blank() -> CGImage {
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        return ctx.makeImage()!
    }

    func testFindsQRCodePayload() async throws {
        let result = try await ContentScanner.scan(qrImage("https://github.com/akelu520/Reticle"))
        XCTAssertEqual(result.codes, ["https://github.com/akelu520/Reticle"])
    }

    func testBlankImageHasNothing() async throws {
        let result = try await ContentScanner.scan(blank())
        XCTAssertEqual(result, ScanResult(hasText: false, codes: []))
    }
}
