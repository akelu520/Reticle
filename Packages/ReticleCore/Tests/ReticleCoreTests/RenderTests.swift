import CoreGraphics
import XCTest
@testable import ReticleCore

final class RenderTests: XCTestCase {
    /// White image with a black/white checker in the top-left 40×40 so mosaic has something to average.
    func makeBase(width: Int = 200, height: Int = 100) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for y in stride(from: 0, to: 40, by: 2) {
            for x in stride(from: (y / 2) % 2 * 2, to: 40, by: 4) {
                // CG bitmap y-up: top-left region is y in [height-40, height).
                ctx.fill(CGRect(x: x, y: height - 40 + y, width: 2, height: 2))
            }
        }
        return ctx.makeImage()!
    }

    /// RGBA of pixel (x, y) with a top-left origin.
    func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let i = (y * image.width + x) * 4
        return [data[i], data[i + 1], data[i + 2], data[i + 3]]
    }

    let style = Style(color: .red, lineWidth: 4, fontSize: 20)

    func testNoAnnotationsIsPlainCrop() {
        let out = Compositor.render(base: makeBase(), pixelated: nil, document: Document(), crop: CGRect(x: 0, y: 0, width: 50, height: 50))
        XCTAssertEqual(out?.width, 50)
    }

    func testRectStrokeLandsAtTopLeftCoordinates() throws {
        let doc = Document(annotations: [Annotation(kind: .rect, points: [CGPoint(x: 60, y: 20), CGPoint(x: 120, y: 80)], style: style)])
        let out = try XCTUnwrap(Compositor.render(base: makeBase(), pixelated: nil, document: doc, crop: CGRect(x: 50, y: 0, width: 100, height: 100)))
        XCTAssertEqual(out.width, 100)
        // Left edge x=60 → crop x=10; top edge y=20.
        let edge = pixel(out, 10, 50)
        XCTAssertGreaterThan(edge[0], 200)
        XCTAssertLessThan(edge[1], 120)
        XCTAssertEqual(pixel(out, 40, 50), [255, 255, 255, 255], "inside stays untouched")
        let top = pixel(out, 40, 20)
        XCTAssertGreaterThan(top[0], 200)
        XCTAssertLessThan(top[2], 120)
    }

    func testArrowFillsNearTip() throws {
        let doc = Document(annotations: [Annotation(kind: .arrow, points: [CGPoint(x: 100, y: 50), CGPoint(x: 190, y: 50)], style: style)])
        let out = try XCTUnwrap(Compositor.render(base: makeBase(), pixelated: nil, document: doc, crop: CGRect(x: 0, y: 0, width: 200, height: 100)))
        XCTAssertLessThan(pixel(out, 180, 50)[1], 120)
        XCTAssertEqual(pixel(out, 180, 30), [255, 255, 255, 255])
    }

    func testMosaicBoxAveragesChecker() throws {
        let base = makeBase()
        let pix = try XCTUnwrap(Mosaic.pixelate(base, blockSize: 20))
        XCTAssertEqual(pix.width, base.width)
        let doc = Document(annotations: [Annotation(kind: .mosaicBox, points: [.zero, CGPoint(x: 40, y: 40)], style: style)])
        let out = try XCTUnwrap(Compositor.render(base: base, pixelated: pix, document: doc, crop: CGRect(x: 0, y: 0, width: 200, height: 100)))
        // Checker averages to mid gray instead of pure black/white.
        let p = pixel(out, 5, 5)
        XCTAssertGreaterThan(p[0], 60)
        XCTAssertLessThan(p[0], 200)
        XCTAssertEqual(pixel(out, 5, 5), pixel(out, 6, 6), "block is uniform")
        XCTAssertEqual(pixel(out, 100, 80), [255, 255, 255, 255], "outside the box untouched")
    }

    func testTextAndLabelDrawSomething() throws {
        let doc = Document(annotations: [
            Annotation(kind: .text, points: [CGPoint(x: 10, y: 50)], style: style, text: "Hi"),
            Annotation(kind: .label, points: [CGPoint(x: 120, y: 70)], style: style, text: "A"),
        ])
        let out = try XCTUnwrap(Compositor.render(base: makeBase(), pixelated: nil, document: doc, crop: CGRect(x: 0, y: 0, width: 200, height: 100)))
        let textArea = (10..<40).flatMap { x in (50..<75).map { y in pixel(out, x, y) } }
        XCTAssertTrue(textArea.contains { $0[1] < 150 }, "red glyph pixels in the text box")
        XCTAssertLessThan(pixel(out, 120, 70)[1], 150, "anchor dot")
    }

    func testWatermarkTintsImageAndRespectsCrop() throws {
        let doc = Document(watermark: Watermark(text: "WATERMARK", opacity: 1, color: .black, fontSize: 14))
        let crop = CGRect(x: 100, y: 0, width: 100, height: 100)
        let out = try XCTUnwrap(Compositor.render(base: makeBase(), pixelated: nil, document: doc, crop: crop))
        let all = (0..<100).flatMap { x in stride(from: 0, to: 100, by: 2).map { y in pixel(out, x, y)[0] } }
        XCTAssertTrue(all.contains { $0 < 128 })
    }

    func testHitTesting() {
        let rect = Annotation(kind: .rect, points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)], style: style)
        XCTAssertTrue(rect.hitTest(CGPoint(x: 11, y: 30), tolerance: 3))
        XCTAssertFalse(rect.hitTest(CGPoint(x: 30, y: 30), tolerance: 3))
        let pen = Annotation(kind: .pen, points: [.zero, CGPoint(x: 100, y: 0)], style: style)
        XCTAssertTrue(pen.hitTest(CGPoint(x: 50, y: 3), tolerance: 3))
        XCTAssertFalse(pen.hitTest(CGPoint(x: 50, y: 20), tolerance: 3))
        let text = Annotation(kind: .text, points: [CGPoint(x: 0, y: 0)], style: style, text: "Hello")
        XCTAssertTrue(text.hitTest(CGPoint(x: 5, y: 5), tolerance: 0))
    }

    func testPaintOrderPutsMosaicUnderShapes() {
        let shape = Annotation(kind: .rect, points: [.zero, CGPoint(x: 5, y: 5)], style: style)
        let mosaic = Annotation(kind: .mosaicBox, points: [.zero, CGPoint(x: 5, y: 5)], style: style)
        let text = Annotation(kind: .text, points: [.zero], style: style, text: "x")
        XCTAssertEqual(Document.paintOrder([text, shape, mosaic]).map(\.kind), [.mosaicBox, .rect, .text])
    }
}
