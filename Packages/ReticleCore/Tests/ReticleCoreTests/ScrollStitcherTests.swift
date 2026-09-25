import CoreGraphics
import XCTest
@testable import ReticleCore

final class ScrollStitcherTests: XCTestCase {
    /// A tall "page": text-like bars of random widths and grays with blank gaps,
    /// deterministic so failures are reproducible.
    static func makePage(width: Int = 320, height: Int = 2400) -> CGImage {
        var rng = SplitMix(seed: 42)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var y = 0
        while y < height {
            let lineHeight = 6 + Int(rng.next() % 10)
            var x = 8
            while x < width - 8 {
                let w = 4 + Int(rng.next() % 40)
                let g = CGFloat(rng.next() % 200) / 255
                ctx.setFillColor(CGColor(gray: g, alpha: 1))
                ctx.fill(CGRect(x: x, y: height - y - lineHeight, width: min(w, width - 8 - x), height: lineHeight))
                x += w + 3 + Int(rng.next() % 6)
            }
            y += lineHeight + 4 + Int(rng.next() % 8)
        }
        return ctx.makeImage()!
    }

    static let page = makePage()

    func window(at y: Int, height: Int = 500) -> CGImage {
        Self.page.cropping(to: CGRect(x: 0, y: y, width: Self.page.width, height: height))!
    }

    func bytes(_ image: CGImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    func assertMatchesPage(_ s: ScrollStitcher, from y0: Int, to y1: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let out = try XCTUnwrap(s.compose(), file: file, line: line)
        XCTAssertEqual(out.height, y1 - y0, file: file, line: line)
        let expected = Self.page.cropping(to: CGRect(x: 0, y: y0, width: Self.page.width, height: y1 - y0))!
        XCTAssertEqual(bytes(out), bytes(expected), "stitched image differs from the page", file: file, line: line)
    }

    func testScrollingDownReconstructsPage() throws {
        let s = ScrollStitcher()
        XCTAssertEqual(s.add(window(at: 0)), .started)
        XCTAssertEqual(s.add(window(at: 37)), .moved(37))
        XCTAssertEqual(s.add(window(at: 37)), .unchanged)
        XCTAssertEqual(s.add(window(at: 250)), .moved(213))
        XCTAssertEqual(s.add(window(at: 640)), .moved(390))
        XCTAssertEqual(s.add(window(at: 1001)), .moved(361))
        try assertMatchesPage(s, from: 0, to: 1501)
    }

    func testScrollingUpPrependsContent() throws {
        let s = ScrollStitcher()
        _ = s.add(window(at: 1200))
        XCTAssertEqual(s.add(window(at: 1100)), .moved(-100))
        XCTAssertEqual(s.add(window(at: 800)), .moved(-300))
        XCTAssertEqual(s.add(window(at: 1000)), .moved(200), "scrolling back down over known content")
        try assertMatchesPage(s, from: 800, to: 1700)
    }

    func testTooLargeJumpIsMismatchAndRecovers() throws {
        let s = ScrollStitcher()
        _ = s.add(window(at: 0))
        XCTAssertEqual(s.add(window(at: 1500)), .mismatch, "no overlap with the reference frame")
        XCTAssertEqual(s.add(window(at: 300)), .moved(300), "compares against the last good frame")
        try assertMatchesPage(s, from: 0, to: 800)
    }

    func testHeightLimit() {
        let s = ScrollStitcher(maxHeight: 700)
        _ = s.add(window(at: 0))
        XCTAssertEqual(s.add(window(at: 300)), .moved(300))
        XCTAssertEqual(s.add(window(at: 500)), .limitReached)
        XCTAssertEqual(s.height, 800)
    }

    func testPreviewScalesDown() throws {
        let s = ScrollStitcher()
        _ = s.add(window(at: 0))
        _ = s.add(window(at: 200))
        let preview = try XCTUnwrap(s.compose(scale: 0.25))
        XCTAssertEqual(preview.width, 80)
        XCTAssertEqual(preview.height, 175)
    }
}

/// Small deterministic PRNG for test fixtures.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
