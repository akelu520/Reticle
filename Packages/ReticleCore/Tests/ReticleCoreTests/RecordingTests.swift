import CoreGraphics
import ImageIO
import XCTest
@testable import ReticleCore

final class RecordingTests: XCTestCase {
    func testDurationFormat() {
        XCTAssertEqual(DurationFormat.string(0), "00:00")
        XCTAssertEqual(DurationFormat.string(7.9), "00:07")
        XCTAssertEqual(DurationFormat.string(754), "12:34")
        XCTAssertEqual(DurationFormat.string(3723), "1:02:03")
    }

    func testEvenPixelSize() {
        XCTAssertEqual(RecordingLimits.evenPixelSize(CGSize(width: 1211, height: 689)), CGSize(width: 1210, height: 688))
        XCTAssertEqual(RecordingLimits.evenPixelSize(CGSize(width: 1, height: 1)), CGSize(width: 2, height: 2))
    }

    func testGIFFrameTimes() {
        let t = GIFPlan.frameTimes(start: 1, end: 1.35)
        XCTAssertEqual(t.count, 4)
        XCTAssertEqual(t[0], 1, accuracy: 1e-9)
        XCTAssertEqual(t[3], 1.3, accuracy: 1e-9)
        XCTAssertTrue(GIFPlan.frameTimes(start: 2, end: 2).isEmpty)
    }

    func testGIFOutputSize() {
        XCTAssertEqual(GIFPlan.outputSize(for: CGSize(width: 1920, height: 1080)), CGSize(width: 960, height: 540))
        XCTAssertEqual(GIFPlan.outputSize(for: CGSize(width: 600, height: 1200)), CGSize(width: 480, height: 960))
        XCTAssertEqual(GIFPlan.outputSize(for: CGSize(width: 400, height: 300)), CGSize(width: 400, height: 300))
    }

    func testGIFWriterProducesAnimatedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reticle-test-\(UUID()).gif")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try XCTUnwrap(GIFWriter(url: url, frameCount: 3, frameDelay: 0.1))
        for g in [0.0, 0.5, 1.0] {
            let ctx = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(gray: g, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
            writer.add(ctx.makeImage()!)
        }
        XCTAssertTrue(writer.finish())
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(src), 3)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 1, nil) as? [String: Any]
        let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        XCTAssertEqual(gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0, 0.1, accuracy: 0.001)
    }

    func testPurgeRemovesOnlyOldFiles() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("reticle-purge-\(UUID())")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let old = dir.appendingPathComponent("old.mp4"), fresh = dir.appendingPathComponent("new.mp4")
        try Data([1]).write(to: old)
        try Data([2]).write(to: fresh)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -2 * 86400)], ofItemAtPath: old.path)
        XCTAssertEqual(TemporaryFiles.purge(in: dir, olderThan: Date(timeIntervalSinceNow: -86400)), 1)
        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path))
    }
}
