import CoreGraphics
import ImageIO
import XCTest
@testable import ReticleCore

final class ExportTests: XCTestCase {
    func makeImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testCropUsesTopLeftPixelRect() {
        let img = makeImage(width: 100, height: 80)
        let cropped = Compositor.crop(img, to: CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(cropped?.width, 30)
        XCTAssertEqual(cropped?.height, 40)
    }

    func testCropClampsToImage() {
        let img = makeImage(width: 100, height: 80)
        let cropped = Compositor.crop(img, to: CGRect(x: 90, y: 70, width: 50, height: 50))
        XCTAssertEqual(cropped?.width, 10)
        XCTAssertEqual(cropped?.height, 10)
        XCTAssertNil(Compositor.crop(img, to: CGRect(x: 200, y: 200, width: 5, height: 5)))
    }

    func testPNGRoundTrip() throws {
        let data = try XCTUnwrap(ImageEncoder.png(makeImage(width: 12, height: 7)))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(decoded.width, 12)
        XCTAssertEqual(decoded.height, 7)
    }

    func testDefaultFileName() {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 5; c.hour = 8; c.minute = 3; c.second = 9
        let date = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(FileNaming.screenshotName(for: date, timeZone: .current), "Reticle_2026-09-05_08-03-09.png")
    }
}
