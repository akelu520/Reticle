import Foundation
import ReticleCore

/// Typed access to user settings stored in UserDefaults.
enum Preferences {
    private static let defaults = UserDefaults.standard

    static var captureHotkey: HotkeyCombo {
        get { decode("captureHotkey") ?? .defaultCapture }
        set { encode(newValue, "captureHotkey") }
    }

    static var recordHotkey: HotkeyCombo {
        get { decode("recordHotkey") ?? .defaultRecord }
        set { encode(newValue, "recordHotkey") }
    }

    /// 保存截图历史 (最近截图), on by default.
    static var historyEnabled: Bool {
        get { defaults.object(forKey: "historyEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "historyEnabled") }
    }

    static var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: "saveDirectory") { return URL(fileURLWithPath: path, isDirectory: true) }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        set { defaults.set(newValue.path, forKey: "saveDirectory") }
    }

    private static func decode<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
