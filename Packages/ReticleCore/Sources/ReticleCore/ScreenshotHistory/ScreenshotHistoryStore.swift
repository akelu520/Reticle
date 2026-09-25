import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ScreenshotHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let pixelWidth: Int
    public let pixelHeight: Int

    var imageName: String { "\(id.uuidString).png" }
    var thumbnailName: String { "\(id.uuidString)-thumb.png" }
}

/// Recent screenshots on disk: one PNG plus a small thumbnail per entry and an
/// `index.json`, newest first, capped at `limit`. Not thread-safe; use from one queue.
public final class ScreenshotHistoryStore {
    public static let defaultLimit = 20
    /// Longest side of thumbnails, in pixels (80 pt menu images at 2×).
    public static let thumbnailMaxPixels = 160

    public let directory: URL
    public let limit: Int
    public private(set) var entries: [ScreenshotHistoryEntry] = []
    private let fileManager: FileManager

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    public init(directory: URL, limit: Int = defaultLimit, fileManager: FileManager = .default) {
        self.directory = directory
        self.limit = limit
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    public func imageURL(for entry: ScreenshotHistoryEntry) -> URL {
        directory.appendingPathComponent(entry.imageName)
    }

    public func thumbnailURL(for entry: ScreenshotHistoryEntry) -> URL {
        directory.appendingPathComponent(entry.thumbnailName)
    }

    /// Stores `png`, makes its thumbnail, and drops the oldest entries beyond `limit`.
    @discardableResult
    public func add(png: Data, date: Date = Date()) throws -> ScreenshotHistoryEntry {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let entry = ScreenshotHistoryEntry(id: UUID(), date: date, pixelWidth: width, pixelHeight: height)
        try png.write(to: imageURL(for: entry), options: .atomic)
        if let thumb = Self.thumbnail(from: source) {
            try thumb.write(to: thumbnailURL(for: entry), options: .atomic)
        }
        entries.insert(entry, at: 0)
        while entries.count > limit {
            deleteFiles(of: entries.removeLast())
        }
        try saveIndex()
        return entry
    }

    public func remove(_ id: UUID) throws {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        deleteFiles(of: entries.remove(at: i))
        try saveIndex()
    }

    public func clear() throws {
        entries.forEach(deleteFiles)
        entries.removeAll()
        try saveIndex()
    }

    // MARK: - Persistence

    /// Reads the index, dropping entries whose image is gone and files no entry owns.
    /// A missing or corrupt index starts an empty history instead of failing.
    private func load() {
        let decoded = (try? Data(contentsOf: indexURL)).flatMap { try? JSONDecoder().decode([ScreenshotHistoryEntry].self, from: $0) } ?? []
        entries = Array(decoded.filter { fileManager.fileExists(atPath: imageURL(for: $0).path) }.prefix(limit))
        let owned = Set(entries.flatMap { [$0.imageName, $0.thumbnailName] } + ["index.json"])
        for name in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] where !owned.contains(name) && name.hasSuffix(".png") {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        if entries != decoded { try? saveIndex() }
    }

    /// Default Codable date encoding on both sides: exact round trip, sub-second included.
    private func saveIndex() throws {
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }

    private func deleteFiles(of entry: ScreenshotHistoryEntry) {
        try? fileManager.removeItem(at: imageURL(for: entry))
        try? fileManager.removeItem(at: thumbnailURL(for: entry))
    }

    static func thumbnail(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return ImageEncoder.png(thumb)
    }
}
