/// A global shortcut: a virtual key code plus modifiers. Independent of AppKit
/// so it can be stored and unit-tested.
public struct HotkeyCombo: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘⇧A.
    public static let defaultCapture = HotkeyCombo(keyCode: 0x00, modifiers: [.command, .shift])
    /// ⌥⇧R.
    public static let defaultRecord = HotkeyCombo(keyCode: 0x0F, modifiers: [.option, .shift])

    /// Global shortcuts need at least one of ⌘ ⌥ ⌃, otherwise they swallow typing.
    public var isValid: Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    /// Modifier mask for Carbon `RegisterEventHotKey` (cmdKey, shiftKey, optionKey, controlKey).
    public var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= 256 }
        if modifiers.contains(.shift) { m |= 512 }
        if modifiers.contains(.option) { m |= 2048 }
        if modifiers.contains(.control) { m |= 4096 }
        return m
    }

    /// Standard macOS order: ⌃⌥⇧⌘ then the key.
    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (Self.keyNames[keyCode] ?? "#\(keyCode)")
    }

    /// ANSI virtual key codes (Carbon kVK_*) to display names.
    static let keyNames: [UInt32: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
        0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
        0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
        0x1C: "8", 0x19: "9",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7",
        0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x31: "Space", 0x32: "`", 0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]", 0x2A: "\\",
        0x29: ";", 0x27: "'", 0x2B: ",", 0x2F: ".", 0x2C: "/",
    ]
}
