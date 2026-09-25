import ReticleCore

extension Preferences {
    static func hotkey(for action: HotkeyCenter.Action) -> HotkeyCombo {
        action == .capture ? captureHotkey : recordHotkey
    }

    static func setHotkey(_ combo: HotkeyCombo, for action: HotkeyCenter.Action) {
        if action == .capture { captureHotkey = combo } else { recordHotkey = combo }
    }
}
