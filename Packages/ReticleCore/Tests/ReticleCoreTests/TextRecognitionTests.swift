import CoreGraphics
import CoreText
import XCTest
@testable import ReticleCore

final class TextRecognitionTests: XCTestCase {
    func line(_ t: String, _ x: CGFloat, _ y: CGFloat, w: CGFloat = 0.2, h: CGFloat = 0.05) -> RecognizedLine {
        RecognizedLine(text: t, box: CGRect(x: x, y: y, width: w, height: h))
    }

    func testReadingOrderRowsThenColumns() {
        let lines = [
            line("world", 0.5, 0.101),
            line("second", 0.1, 0.3),
            line("Hello", 0.1, 0.1),
        ]
        XCTAssertEqual(ReadingOrder.text(from: lines), "Hello world\nsecond")
    }

    func testReadingOrderJoinsCJKWithoutSpace() {
        XCTAssertEqual(ReadingOrder.text(from: [line("截图", 0.1, 0.1), line("工具", 0.4, 0.1)]), "截图工具")
        XCTAssertEqual(ReadingOrder.text(from: [line("Reticle", 0.1, 0.1), line("截图", 0.4, 0.1)]), "Reticle截图")
    }

    func testLinkDetection() {
        let text = "官网 https://example.com/a?b=1 和 www.apple.com 以及 mail@x.com"
        let links = LinkDetector.links(in: text)
        XCTAssertEqual(links.map(\.url.host), ["example.com", "www.apple.com"])
        XCTAssertEqual((text as NSString).substring(with: links[0].range), "https://example.com/a?b=1")
    }

    func testDetectedSource() {
        XCTAssertEqual(TranslationLanguages.detectedSource(for: "这是一个好用的截图工具，可以提取文字"), "zh-Hans")
        XCTAssertEqual(TranslationLanguages.detectedSource(for: "This is a handy screenshot tool"), "en")
        XCTAssertEqual(TranslationLanguages.detectedSource(for: "Reticle demo"), "en", "short Latin text")
        XCTAssertNil(TranslationLanguages.detectedSource(for: "12345"))
    }

    func testDefaultTranslationTarget() {
        XCTAssertEqual(TranslationLanguages.defaultTarget(for: "这是一个好用的截图工具，可以提取文字"), "en")
        XCTAssertEqual(TranslationLanguages.defaultTarget(for: "This is a handy screenshot tool"), "zh-Hans")
    }

    /// Real Vision OCR on a rendered image.
    func testRecognizesRenderedText() async throws {
        let w = 800, h = 200
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        TextMetrics.draw("Hello Reticle", at: CGPoint(x: 40, y: 30), fontSize: 56, color: .black, in: ctx)
        TextMetrics.draw("截图工具", at: CGPoint(x: 40, y: 110), fontSize: 56, color: .black, in: ctx)
        let image = try XCTUnwrap(ctx.makeImage())
        let text = try await TextRecognizer.text(in: image)
        XCTAssertTrue(text.contains("Hello Reticle"), text)
        XCTAssertTrue(text.contains("截图工具"), text)
        XCTAssertLessThan(text.range(of: "Hello")!.lowerBound, text.range(of: "截图")!.lowerBound, "top line first")
    }
}
