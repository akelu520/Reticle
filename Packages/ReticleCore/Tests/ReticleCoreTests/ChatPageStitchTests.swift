import CoreGraphics
import ImageIO
import XCTest
@testable import ReticleCore

/// A dark chat page: light text on a dark background, an input box fixed at the bottom of the
/// viewport with a gradient above it that fades the scrolling text out, and a floating
/// "scroll to bottom" button just above the fade.
final class ChatPageStitchTests: XCTestCase {
    static let width = 720, viewport = 600, pageHeight = 2600
    static let inputHeight = 50, fadeHeight = 90
    /// Optional title bar with a fade below it, fixed at the top.
    static let titleHeight = 44, topFadeHeight = 50
    /// The floating button sits just above the bottom fade.
    static let buttonTop = viewport - inputHeight - fadeHeight - 42
    static let background = CGColor(gray: 0.12, alpha: 1)

    static let page: CGImage = {
        var rng = SplitMix(seed: 11)
        let ctx = CGContext(data: nil, width: width, height: pageHeight, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: pageHeight))
        var y = 30
        while y < pageHeight - 60 {
            let heading = rng.next() % 5 == 0
            let lines = heading ? 1 : 1 + Int(rng.next() % 4)
            for _ in 0..<lines {
                // Words: light bars of varying width on one text line.
                var x = 40
                let end = 140 + Int(rng.next() % 520)
                while x < end {
                    let w = 10 + Int(rng.next() % 50)
                    ctx.setFillColor(CGColor(gray: heading ? 0.95 : 0.8, alpha: 1))
                    ctx.fill(CGRect(x: x, y: pageHeight - y - (heading ? 14 : 11), width: min(w, end - x), height: heading ? 14 : 11))
                    x += w + 5
                }
                y += 24
            }
            y += 16
        }
        return ctx.makeImage()!
    }()

    /// The viewport at scroll `offset`, with the fixed input box, fade and button on top.
    static func frame(at offset: Int, button: Bool = true, title: Bool = false) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: viewport, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let crop = page.cropping(to: CGRect(x: 0, y: offset, width: width, height: viewport))!
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: viewport))
        // Fade: transparent at the top, the background color at the bottom (just above the input box).
        for i in 0..<fadeHeight {
            ctx.setFillColor(CGColor(gray: 0.12, alpha: CGFloat(i) / CGFloat(fadeHeight)))
            ctx.fill(CGRect(x: 0, y: inputHeight + fadeHeight - 1 - i, width: width, height: 1))
        }
        // Input box.
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: inputHeight))
        ctx.setFillColor(CGColor(gray: 0.22, alpha: 1))
        ctx.fill(CGRect(x: 30, y: 6, width: width - 60, height: inputHeight - 12))
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 50, y: 20, width: 140, height: 10))
        if title {
            for i in 0..<topFadeHeight {
                ctx.setFillColor(CGColor(gray: 0.12, alpha: CGFloat(i) / CGFloat(topFadeHeight)))
                ctx.fill(CGRect(x: 0, y: viewport - titleHeight - topFadeHeight + i, width: width, height: 1))
            }
            ctx.setFillColor(background)
            ctx.fill(CGRect(x: 0, y: viewport - titleHeight, width: width, height: titleHeight))
            ctx.setFillColor(CGColor(gray: 0.7, alpha: 1))
            ctx.fill(CGRect(x: 30, y: viewport - 28, width: 180, height: 12))
        }
        if button {
            ctx.setFillColor(CGColor(gray: 0.3, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: width / 2 - 16, y: inputHeight + fadeHeight + 10, width: 32, height: 32))
            ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
            ctx.fill(CGRect(x: width / 2 - 2, y: inputHeight + fadeHeight + 18, width: 4, height: 16))
        }
        return ctx.makeImage()!
    }

    static func gray(_ image: CGImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height))
    }

    /// 8-row bands (from the top) of `image` rows `0..<rows` that differ from the page.
    static func badBands(_ image: CGImage, rows: Range<Int>) -> [Int] {
        let a = gray(image), b = gray(page), w = width
        var bad: [Int] = []
        for band in stride(from: rows.lowerBound, to: min(rows.upperBound, image.height) - 8, by: 8) {
            var total = 0
            for y in band..<(band + 8) { for x in 0..<w { total += abs(Int(a[y * w + x]) - Int(b[y * w + x])) } }
            if Double(total) / Double(8 * w) > 3 { bad.append(band) }
        }
        return bad
    }

    func testDarkChatPageWithFixedFooterStitchesCleanly() throws {
        let s = ScrollStitcher()
        _ = s.add(Self.frame(at: 0))
        var offset = 0, speed = 0
        var rng = SplitMix(seed: 3)
        while offset < Self.pageHeight - Self.viewport {
            speed = max(10, min(120, speed + Int(rng.next() % 41) - 15))
            offset = min(offset + speed, Self.pageHeight - Self.viewport)
            _ = s.add(Self.frame(at: offset))
        }
        let image = try XCTUnwrap(s.compose())
        if let out = ProcessInfo.processInfo.environment["STITCH_OUT"],
           let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        // Everything above the last screen's fixed button, fade and input box must be the page itself.
        XCTAssertEqual(image.height, Self.pageHeight)
        let bad = Self.badBands(image, rows: 0..<(Self.pageHeight - Self.viewport + Self.buttonTop))
        XCTAssertTrue(bad.isEmpty, "\(bad.count) bands differ from the page, first at rows \(bad.prefix(8))")
    }

    /// Scrolling from the bottom up, with a title bar and fade fixed at the top as well.
    func testScrollingUpWithFixedHeaderAndFooter() throws {
        let s = ScrollStitcher()
        var offset = Self.pageHeight - Self.viewport, speed = 0
        _ = s.add(Self.frame(at: offset, title: true))
        var rng = SplitMix(seed: 5)
        while offset > 0 {
            speed = max(10, min(120, speed + Int(rng.next() % 41) - 15))
            offset = max(offset - speed, 0)
            _ = s.add(Self.frame(at: offset, title: true))
        }
        let image = try XCTUnwrap(s.compose())
        if let out = ProcessInfo.processInfo.environment["STITCH_OUT_UP"],
           let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        XCTAssertEqual(image.height, Self.pageHeight)
        // The last screen (at the top) keeps its title bar and fade; the first (at the bottom) its footer.
        let bad = Self.badBands(image, rows: (Self.titleHeight + Self.topFadeHeight)..<(Self.pageHeight - Self.viewport + Self.buttonTop))
        XCTAssertTrue(bad.isEmpty, "\(bad.count) bands differ from the page, first at rows \(bad.prefix(8))")
    }
}
