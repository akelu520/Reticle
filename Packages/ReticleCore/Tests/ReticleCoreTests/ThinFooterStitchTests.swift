import CoreGraphics
import XCTest
@testable import ReticleCore

/// A light marketing page captured with a thin line fixed at the bottom of the region (the
/// browser window's edge, or a page's 1–3 px fixed border): it must not show up at every strip
/// junction, and the page rows under it must not go missing.
final class ThinFooterStitchTests: XCTestCase {
    static let width = 720, viewport = 560, pageHeight = 2600, lineHeight = 3

    static let page: CGImage = {
        var rng = SplitMix(seed: 21)
        let ctx = CGContext(data: nil, width: width, height: pageHeight, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // A soft vertical gradient, white to pale lavender, like the page in the report.
        for y in 0..<pageHeight {
            let t = CGFloat(y % 900) / 900
            ctx.setFillColor(CGColor(red: 1 - 0.03 * t, green: 1 - 0.03 * t, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: pageHeight - y - 1, width: width, height: 1))
        }
        var y = 30
        while y < pageHeight - 80 {
            if rng.next() % 3 == 0 {
                // A card: light gray box with a title and two lines of gray text.
                let h = 90 + Int(rng.next() % 60), x = 40 + Int(rng.next() % 200), w = 220 + Int(rng.next() % 200)
                ctx.setFillColor(CGColor(gray: 0.96, alpha: 1))
                ctx.fill(CGRect(x: x, y: pageHeight - y - h, width: w, height: h))
                ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
                ctx.fill(CGRect(x: x + 16, y: pageHeight - y - 30, width: 80 + Int(rng.next() % 100), height: 12))
                ctx.setFillColor(CGColor(gray: 0.45, alpha: 1))
                ctx.fill(CGRect(x: x + 16, y: pageHeight - y - 56, width: 120 + Int(rng.next() % 80), height: 10))
                ctx.fill(CGRect(x: x + 16, y: pageHeight - y - 74, width: 60 + Int(rng.next() % 80), height: 10))
                y += h + 24
            } else {
                // A line of dark text.
                var x = 40
                let end = 160 + Int(rng.next() % 480)
                while x < end {
                    let w = 12 + Int(rng.next() % 60)
                    ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
                    ctx.fill(CGRect(x: x, y: pageHeight - y - 14, width: min(w, end - x), height: 14))
                    x += w + 6
                }
                y += 34
            }
        }
        return ctx.makeImage()!
    }()

    /// The region at scroll `offset`, with a thin light-gray line fixed along its bottom edge.
    static func frame(at offset: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: viewport, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(page.cropping(to: CGRect(x: 0, y: offset, width: width, height: viewport))!, in: CGRect(x: 0, y: 0, width: width, height: viewport))
        ctx.setFillColor(CGColor(gray: 0.86, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: lineHeight))
        return ctx.makeImage()!
    }

    static func gray(_ image: CGImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height))
    }

    func testThinFixedLineAtTheBottomStaysOut() throws {
        let s = ScrollStitcher()
        _ = s.add(Self.frame(at: 0))
        var offset = 0, speed = 0
        var rng = SplitMix(seed: 9)
        while offset < Self.pageHeight - Self.viewport {
            speed = max(8, min(110, speed + Int(rng.next() % 41) - 15))
            offset = min(offset + speed, Self.pageHeight - Self.viewport)
            _ = s.add(Self.frame(at: offset))
        }
        let image = try XCTUnwrap(s.compose())
        XCTAssertEqual(image.height, Self.pageHeight)
        // Everything above the last screen's line must be the page itself.
        let a = Self.gray(image), b = Self.gray(Self.page), w = Self.width
        var bad: [Int] = []
        for y in 0..<min(image.height, Self.pageHeight - Self.lineHeight) {
            var d = 0
            for x in stride(from: 0, to: w, by: 2) { d += abs(Int(a[y * w + x]) - Int(b[y * w + x])) }
            if Double(d) / Double(w / 2) > 4 { bad.append(y) }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) rows differ from the page, first at \(bad.prefix(10))")
    }
}
