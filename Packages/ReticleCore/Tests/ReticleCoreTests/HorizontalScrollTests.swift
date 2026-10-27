import CoreGraphics
import XCTest
@testable import ReticleCore

final class HorizontalScrollTests: XCTestCase {
    /// A wide page: columns of text-like bars, deterministic.
    static let page: CGImage = {
        var rng = SplitMix(seed: 31)
        let w = 3000, h = 360
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var x = 10
        while x < w - 10 {
            var y = 10
            let colWidth = 60 + Int(rng.next() % 120)
            while y < h - 20 {
                let lh = 8 + Int(rng.next() % 10)
                ctx.setFillColor(CGColor(gray: CGFloat(rng.next() % 200) / 255, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 10 + Int(rng.next() % UInt64(colWidth)), height: lh))
                y += lh + 6
            }
            x += colWidth + 14
        }
        return ctx.makeImage()!
    }()

    static let viewport = 600

    /// The viewport at horizontal scroll `offset`, optionally with a sidebar fixed on the left.
    static func frame(at offset: Int, sidebar: Bool = false) -> CGImage {
        let crop = page.cropping(to: CGRect(x: offset, y: 0, width: viewport, height: page.height))!
        guard sidebar else { return crop }
        let ctx = CGContext(data: nil, width: viewport, height: page.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: viewport, height: page.height))
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 70, height: page.height))
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        for i in 0..<6 { ctx.fill(CGRect(x: 14, y: 20 + i * 50, width: 42, height: 12)) }
        return ctx.makeImage()!
    }

    static func bytes(_ image: CGImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    func testTransposeSwapsAxesAndIsItsOwnInverse() throws {
        let img = Self.page.cropping(to: CGRect(x: 0, y: 0, width: 50, height: 30))!
        let t = try XCTUnwrap(ImageTranspose.transposed(img))
        XCTAssertEqual(t.width, 30)
        XCTAssertEqual(t.height, 50)
        let back = try XCTUnwrap(ImageTranspose.transposed(t))
        XCTAssertEqual(Self.bytes(back), Self.bytes(img))
        // Pixel (x, y) of the original is (y, x) of the transposed image.
        let a = Self.bytes(img), b = Self.bytes(t)
        for (x, y) in [(3, 7), (40, 2), (12, 29)] {
            XCTAssertEqual(Array(a[(y * 50 + x) * 4..<(y * 50 + x) * 4 + 4]), Array(b[(x * 30 + y) * 4..<(x * 30 + y) * 4 + 4]))
        }
    }

    func testScrollingSidewaysReconstructsTheWidePage() throws {
        let s = ScrollCaptureStitcher()
        var offset = 0
        _ = s.add(Self.frame(at: 0))
        for step in [12, 30, 55, 70, 0, 90, 120, 60, 140, 100, 80, 130, 150, 110, 160, 140, 120, 150] {
            offset = min(offset + step, Self.page.width - Self.viewport)
            _ = s.add(Self.frame(at: offset))
        }
        XCTAssertEqual(s.axis, .horizontal)
        let out = try XCTUnwrap(s.compose())
        XCTAssertEqual(out.height, Self.page.height)
        XCTAssertEqual(out.width, offset + Self.viewport)
        XCTAssertEqual(Self.bytes(out), Self.bytes(Self.page.cropping(to: CGRect(x: 0, y: 0, width: offset + Self.viewport, height: Self.page.height))!),
                       "the stitched image is the page")
    }

    func testVerticalScrollingStaysVertical() throws {
        let s = ScrollCaptureStitcher()
        let tall = ImageTranspose.transposed(Self.page)! // the same content, scrolling down
        let frame = { (y: Int) in tall.cropping(to: CGRect(x: 0, y: y, width: tall.width, height: Self.viewport))! }
        var offset = 0
        _ = s.add(frame(0))
        for step in [20, 40, 60, 80, 100, 90] {
            offset += step
            _ = s.add(frame(offset))
        }
        XCTAssertEqual(s.axis, .vertical)
        let out = try XCTUnwrap(s.compose())
        XCTAssertEqual(out.height, offset + Self.viewport)
        XCTAssertEqual(out.width, tall.width)
    }

    func testSidebarFixedOnTheLeftAppearsOnce() throws {
        let s = ScrollCaptureStitcher()
        var offset = 0
        _ = s.add(Self.frame(at: 0, sidebar: true))
        var rng = SplitMix(seed: 4)
        var speed = 0
        while offset < Self.page.width - Self.viewport {
            speed = max(10, min(120, speed + Int(rng.next() % 41) - 15))
            offset = min(offset + speed, Self.page.width - Self.viewport)
            _ = s.add(Self.frame(at: offset, sidebar: true))
        }
        XCTAssertEqual(s.axis, .horizontal)
        let out = try XCTUnwrap(s.compose())
        XCTAssertEqual(out.width, Self.page.width)
        // Right of the first screen's sidebar (and its edge margin), the image is the page.
        let a = Self.bytes(out), b = Self.bytes(Self.page), w = Self.page.width
        var bad = 0
        for y in stride(from: 0, to: Self.page.height, by: 3) {
            for x in stride(from: 110, to: w, by: 3) where a[(y * w + x) * 4] != b[(y * w + x) * 4] { bad += 1 }
        }
        XCTAssertEqual(bad, 0, "pixels differing from the page")
    }

    /// The page scrolled sideways (or, transposed, down) with a round button fixed in the middle
    /// of the viewport; returns the stitched image and how far it scrolled.
    func stitchWithMidButton(sideways: Bool) throws -> (CGImage, CGImage, Int) {
        let page = sideways ? Self.page : ImageTranspose.transposed(Self.page)!
        let vp = Self.viewport
        func frame(_ o: Int) -> CGImage {
            let w = sideways ? vp : page.width, h = sideways ? page.height : vp
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let crop = sideways ? CGRect(x: o, y: 0, width: vp, height: h) : CGRect(x: 0, y: o, width: w, height: vp)
            ctx.draw(page.cropping(to: crop)!, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(CGColor(gray: 0.3, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: w / 2 - 16, y: h / 2 - 16, width: 32, height: 32))
            return ctx.makeImage()!
        }
        let s = ScrollCaptureStitcher()
        let end = (sideways ? page.width : page.height) - vp
        var o = 0, speed = 0
        var rng = SplitMix(seed: 2)
        _ = s.add(frame(0))
        while o < end {
            speed = max(10, min(110, speed + Int(rng.next() % 41) - 15))
            o = min(o + speed, end)
            _ = s.add(frame(o))
        }
        XCTAssertEqual(s.axis, sideways ? .horizontal : .vertical)
        return (try XCTUnwrap(s.compose()), page, o)
    }

    /// Only the last screen shows the button: elsewhere the image is the page.
    func testFloatingButtonInTheMiddleAppearsOnlyOnTheLastScreen() throws {
        for sideways in [false, true] {
            let (out, page, last) = try stitchWithMidButton(sideways: sideways)
            let a = Self.bytes(out), b = Self.bytes(page), w = page.width
            var bad = 0
            for y in 0..<min(out.height, page.height) {
                for x in stride(from: 0, to: min(out.width, w), by: 2) where a[(y * out.width + x) * 4] != b[(y * w + x) * 4] {
                    // The last screen's own button is how the page really looked.
                    if (sideways ? x : y) < last { bad += 1 }
                }
            }
            XCTAssertEqual(bad, 0, "\(sideways ? "sideways" : "down"): pixels before the last screen differing from the page")
        }
    }
}
