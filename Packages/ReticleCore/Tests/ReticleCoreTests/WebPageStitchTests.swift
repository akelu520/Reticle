import CoreGraphics
import XCTest
@testable import ReticleCore

/// Web-page-like scrolling: repetitive table rows, a watermark and a floating
/// button fixed to the viewport, and hover highlights that change between frames.
final class WebPageStitchTests: XCTestCase {
    static let width = 720, viewport = 560, rowHeight = 64

    /// Page rows 0..<height, top-down: a header (title, tabs, stat cards, filters), then table rows.
    static func drawPage(_ ctx: CGContext, height: Int, offset: Int, hoverRow: Int?) {
        let w = CGFloat(width)
        func fill(_ gray: CGFloat, _ x: Int, _ y: Int, _ rw: Int, _ rh: Int) {
            // Page coordinates are top-down; the context is bottom-up and shows page rows offset..<offset+viewport.
            let top = y - offset
            ctx.setFillColor(CGColor(gray: gray, alpha: 1))
            ctx.fill(CGRect(x: x, y: viewport - top - rh, width: rw, height: rh))
        }
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: CGFloat(viewport)))
        fill(0.1, 8, 4, 120, 14)                       // title
        for i in 0..<3 { fill(0.4, 8 + i * 70, 26, 50, 8) }   // tabs
        for i in 0..<4 { fill(1, 8 + i * 178, 48, 170, 50); fill(0.2, 16 + i * 178, 72, 30, 12) } // stat cards
        fill(1, 8, 110, 704, 30)
        for i in 0..<9 { fill(0.6, 16 + i * 76, 118, 60, 14) } // filters
        fill(0.85, 8, 150, 704, 28)                    // table header
        var y = 180, row = 0
        while y + rowHeight <= height - 40 {
            fill(row == hoverRow ? 0.93 : 1, 8, y, 704, rowHeight - 1)
            fill(0.3, 16, y + 26, 30, 10)                 // id
            fill(0.3, 120, y + 26, 60 + (row % 3) * 8, 10)
            fill(0.45, 330, y + 26, 150, 10)              // bank name
            for l in 0..<5 { fill(0.35, 470, y + 6 + l * 11, 90 + (row * 7 + l * 13) % 40, 7) } // details
            fill(0.45, 600, y + 26, 100, 10)              // actions
            y += rowHeight
            row += 1
        }
        fill(0.7, 8, height - 30, 300, 6)               // scrollbar / pagination
    }

    /// One captured frame at scroll `offset`; fixed overlays are drawn in viewport coordinates.
    static func frame(page height: Int, at offset: Int, hoverRow: Int? = nil, widget: Bool = true, stickyHeader: Bool = false) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: viewport, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        drawPage(ctx, height: height, offset: offset, hoverRow: hoverRow)
        // Watermark fixed to the viewport.
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.08))
        for gy in stride(from: 20, to: viewport, by: 110) { for gx in stride(from: 30, to: width, by: 220) { ctx.fill(CGRect(x: gx, y: gy, width: 90, height: 12)) } }
        // A sticky navigation bar over the top of the viewport.
        if stickyHeader {
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
            ctx.fill(CGRect(x: 0, y: viewport - 44, width: width, height: 44))
            ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
            for i in 0..<5 { ctx.fill(CGRect(x: 16 + i * 90, y: viewport - 28, width: 60, height: 10)) }
        }
        // Floating button fixed at the bottom right.
        if widget {
            ctx.setFillColor(CGColor(red: 0.4, green: 0.3, blue: 0.9, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: width - 30, y: 60, width: 26, height: 26))
        }
        return ctx.makeImage()!
    }

    func testHoverChangeWithoutScrollingDoesNotDuplicate() throws {
        let pageHeight = 900
        let s = ScrollStitcher()
        XCTAssertEqual(s.add(Self.frame(page: pageHeight, at: 0)), .started)
        // The pointer moves over the table: a row highlight changes, nothing scrolls.
        for hover in [0, 1, 2, 3, nil] {
            let r = s.add(Self.frame(page: pageHeight, at: 0, hoverRow: hover))
            XCTAssertTrue(r == .unchanged || r == .mismatch, "hover \(String(describing: hover)) gave \(r)")
        }
        XCTAssertEqual(s.height, Self.viewport)
    }

    func testScrollingRepetitiveTableReconstructsPage() throws {
        let pageHeight = 1400
        let s = ScrollStitcher()
        _ = s.add(Self.frame(page: pageHeight, at: 0))
        var offset = 0
        // Wheel scrolling at 15 fps: small, uneven steps, with the pointer over changing rows.
        for (i, step) in [18, 40, 64, 0, 52, 90, 128, 30, 70, 64, 100, 64].enumerated() {
            offset = min(offset + step, pageHeight - Self.viewport)
            _ = s.add(Self.frame(page: pageHeight, at: offset, hoverRow: i % 4))
        }
        XCTAssertEqual(s.height, offset + Self.viewport, "stitched height should equal the scrolled page height")
    }

    /// One frame's shift is misjudged (here: a frame that jumped too far to compare); later frames
    /// must still land where they match the stitched image instead of drifting and duplicating it.
    func testReturningToTheTopDoesNotDuplicateContent() throws {
        let pageHeight = 1400
        let s = ScrollStitcher()
        _ = s.add(Self.frame(page: pageHeight, at: 0))
        for offset in [60, 130, 200, 260] { _ = s.add(Self.frame(page: pageHeight, at: offset, hoverRow: offset / 64 % 3)) }
        let heightAtBottom = s.height
        // Back up to the top, e.g. to check the start.
        for offset in [180, 90, 20, 0] { _ = s.add(Self.frame(page: pageHeight, at: offset, hoverRow: 1)) }
        XCTAssertEqual(s.height, heightAtBottom, "scrolling back over known content must not add rows")
    }

    /// Frames that match nothing near the expected position but do match elsewhere in the
    /// stitched image are placed there, not prepended or appended as new content.
    func testFrameMatchingKnownContentIsPlacedThere() throws {
        let pageHeight = 1400
        let s = ScrollStitcher()
        _ = s.add(Self.frame(page: pageHeight, at: 0))
        for offset in [80, 160, 240, 320, 400] { _ = s.add(Self.frame(page: pageHeight, at: offset)) }
        let height = s.height
        // A jump straight back to the top: no overlap with the previous frame (400 → 0 exceeds 80% of the viewport? no, but the
        // pairwise estimate may pick a repetitive-row alias); the stitched image already contains this frame at 0.
        let r = s.add(Self.frame(page: pageHeight, at: 0, hoverRow: 2))
        XCTAssertNotEqual(r, .limitReached)
        XCTAssertEqual(s.height, height, "a frame already contained in the image adds nothing")
        // Continuing from the top then scrolling down again extends the image only past the old bottom.
        for offset in [60, 200, 400, 520, 640, 760, 840] { _ = s.add(Self.frame(page: pageHeight, at: offset)) }
        XCTAssertEqual(s.height, 840 + Self.viewport)
    }

    /// Random wheel / trackpad scrolling: speed changes gradually (momentum), with pauses and
    /// short scrolls back up. The image must never grow past what was actually scrolled
    /// (duplicated content) and must cover the whole page once the end is reached.
    func testRandomScrollingNeverDuplicates() throws {
        let pageHeight = 2400, end = pageHeight - Self.viewport
        var rng = SplitMix(seed: 7)
        for run in 0..<40 {
            let s = ScrollStitcher()
            _ = s.add(Self.frame(page: pageHeight, at: 0))
            var offset = 0, deepest = 0, speed = 0
            var i = 0
            while deepest < end, i < 400 {
                // Up to 24 px/frame of acceleration, up to 240 px/frame, mostly downward.
                speed += Int(rng.next() % 49) - 20
                if rng.next() % 30 == 0 { speed = 0 }
                speed = max(-120, min(240, speed))
                offset = max(0, min(offset + speed, end))
                deepest = max(deepest, offset)
                _ = s.add(Self.frame(page: pageHeight, at: offset, hoverRow: i % 5 == 0 ? nil : Int(rng.next() % 30)))
                XCTAssertLessThanOrEqual(s.height, deepest + Self.viewport, "run \(run) frame \(i): duplicated content")
                i += 1
            }
            XCTAssertEqual(s.height, pageHeight, "run \(run): the whole page")
        }
    }

    /// Pixels of the floating button's color in `image`.
    static func widgetPixels(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var n = 0
        for i in 0..<(w * h) where px[i * 4 + 2] > 200 && px[i * 4] < 140 && px[i * 4 + 1] < 110 { n += 1 }
        return n
    }

    /// A button fixed to the viewport appears once in the long image, not in every new strip.
    func testFloatingButtonAppearsOnce() throws {
        let pageHeight = 2400
        let single = Self.widgetPixels(Self.frame(page: pageHeight, at: 0))
        XCTAssertGreaterThan(single, 300)
        let s = ScrollStitcher()
        _ = s.add(Self.frame(page: pageHeight, at: 0))
        var offset = 0
        while offset < pageHeight - Self.viewport {
            offset = min(offset + 70, pageHeight - Self.viewport)
            _ = s.add(Self.frame(page: pageHeight, at: offset, hoverRow: offset / 64 % 5))
        }
        let image = try XCTUnwrap(s.compose())
        XCTAssertEqual(image.height, pageHeight)
        XCTAssertLessThanOrEqual(Self.widgetPixels(image), single + single / 5, "the floating button is repeated")
    }

    /// A sticky top bar never scrolls; the content below it still stitches.
    func testStickyHeaderStitches() throws {
        let pageHeight = 1800
        let s = ScrollStitcher()
        _ = s.add(Self.frame(page: pageHeight, at: 0, stickyHeader: true))
        var offset = 0
        while offset < pageHeight - Self.viewport {
            offset = min(offset + 60, pageHeight - Self.viewport)
            _ = s.add(Self.frame(page: pageHeight, at: offset, stickyHeader: true))
        }
        XCTAssertEqual(s.height, pageHeight)
    }
}
