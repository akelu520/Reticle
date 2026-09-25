import Foundation
import ReticleCore

/// Temporary recording files under Caches: raw captures (deleted on quit) and
/// clipboard exports (kept 24 hours so a paste after closing still works).
enum RecordingStorage {
    private static var root: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Reticle").appendingPathComponent("Recordings")
    }

    static var rawDirectory: URL { directory("raw") }
    static var clipboardDirectory: URL { directory("clipboard") }

    static func newRawURL() -> URL {
        rawDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    }

    static func purgeOnLaunch() {
        TemporaryFiles.purge(in: rawDirectory, olderThan: Date())
        TemporaryFiles.purge(in: clipboardDirectory, olderThan: Date(timeIntervalSinceNow: -24 * 3600))
    }

    static func purgeOnQuit() {
        TemporaryFiles.purge(in: rawDirectory, olderThan: .distantFuture)
    }

    private static func directory(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
