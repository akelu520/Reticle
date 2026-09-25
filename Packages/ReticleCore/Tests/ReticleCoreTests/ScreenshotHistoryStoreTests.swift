import CoreGraphics
import ImageIO
import XCTest
@testable import ReticleCore

final class ScreenshotHistoryStoreTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("reticle-history-\(UUID())")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func png(width: Int, height: Int) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ImageEncoder.png(ctx.makeImage()!)!
    }

    func files() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    }

    func testAddStoresImageThumbnailAndNewestFirst() throws {
        let store = ScreenshotHistoryStore(directory: dir)
        let first = try store.add(png: png(width: 400, height: 200), date: Date(timeIntervalSince1970: 1))
        let second = try store.add(png: png(width: 30, height: 60), date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(store.entries.map(\.id), [second.id, first.id])
        XCTAssertEqual(first.pixelWidth, 400)
        XCTAssertEqual(first.pixelHeight, 200)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(for: first).path))
        let thumb = CGImageSourceCreateWithURL(store.thumbnailURL(for: first) as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        XCTAssertEqual(thumb?.width, ScreenshotHistoryStore.thumbnailMaxPixels)
        XCTAssertEqual(thumb?.height, 80)
    }

    func testLimitDeletesOldestFiles() throws {
        let store = ScreenshotHistoryStore(directory: dir, limit: 3)
        let oldest = try store.add(png: png(width: 10, height: 10))
        for _ in 0..<3 { try store.add(png: png(width: 10, height: 10)) }
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertFalse(store.entries.contains(oldest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: oldest).path))
        XCTAssertEqual(files().count, 3 * 2 + 1, "3 images + 3 thumbnails + index")
    }

    func testPersistsAcrossInstances() throws {
        let a = ScreenshotHistoryStore(directory: dir)
        let entry = try a.add(png: png(width: 12, height: 8), date: Date(timeIntervalSince1970: 1_700_000_000))
        let b = ScreenshotHistoryStore(directory: dir)
        XCTAssertEqual(b.entries, [entry])
    }

    func testCorruptIndexStartsEmptyAndRemovesOrphans() throws {
        let a = ScreenshotHistoryStore(directory: dir)
        try a.add(png: png(width: 10, height: 10))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("index.json"))
        let b = ScreenshotHistoryStore(directory: dir)
        XCTAssertTrue(b.entries.isEmpty)
        XCTAssertEqual(files(), ["index.json"], "orphaned images are cleaned up")
    }

    func testMissingImageDropsEntry() throws {
        let a = ScreenshotHistoryStore(directory: dir)
        let gone = try a.add(png: png(width: 10, height: 10))
        let kept = try a.add(png: png(width: 10, height: 10))
        try FileManager.default.removeItem(at: a.imageURL(for: gone))
        XCTAssertEqual(ScreenshotHistoryStore(directory: dir).entries, [kept])
    }

    func testRemoveAndClear() throws {
        let store = ScreenshotHistoryStore(directory: dir)
        let a = try store.add(png: png(width: 10, height: 10))
        try store.add(png: png(width: 10, height: 10))
        try store.remove(a.id)
        XCTAssertEqual(store.entries.count, 1)
        try store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(files(), ["index.json"])
    }

    func testRejectsNonImageData() {
        let store = ScreenshotHistoryStore(directory: dir)
        XCTAssertThrowsError(try store.add(png: Data("nope".utf8)))
        XCTAssertTrue(store.entries.isEmpty)
    }
}
