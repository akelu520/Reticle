import AppKit
import ReticleCore
import SwiftUI

/// Click to record a new shortcut; Esc cancels. Global hotkeys are suspended
/// while recording so the current shortcut can be pressed again.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var combo: HotkeyCombo
    let onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecording = onRecording
        button.onRecord = { combo = $0 }
        button.combo = combo
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.combo = combo
    }
}

final class RecorderButton: NSButton {
    var combo: HotkeyCombo = .defaultCapture { didSet { refreshTitle() } }
    var onRecord: ((HotkeyCombo) -> Void)?
    var onRecording: ((Bool) -> Void)?
    private var recording = false { didSet { refreshTitle(); onRecording?(recording) } }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggle)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    @objc private func toggle() {
        recording.toggle()
        if recording { window?.makeFirstResponder(self) }
    }

    override func resignFirstResponder() -> Bool {
        if recording { recording = false }
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        if event.keyCode == 53 { // Esc
            recording = false
            return
        }
        var mods: HotkeyCombo.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        let candidate = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
        guard candidate.isValid else {
            NSSound.beep()
            return
        }
        recording = false
        onRecord?(candidate)
    }

    private func refreshTitle() {
        title = recording ? "请按下快捷键…" : combo.displayString
    }
}
