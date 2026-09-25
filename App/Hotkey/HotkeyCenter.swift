import Carbon
import ReticleCore

/// Global shortcuts via Carbon `RegisterEventHotKey`, which does not need the
/// Accessibility permission.
@MainActor
final class HotkeyCenter {
    enum Action: UInt32 { case capture = 1, record = 2 }

    static let shared = HotkeyCenter()

    private var refs: [Action: EventHotKeyRef] = [:]
    private var combos: [Action: HotkeyCombo] = [:]
    private var handlers: [Action: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5254_434C // "RTCL"

    /// Returns false when the system refuses the shortcut (typically already taken).
    func register(_ combo: HotkeyCombo, for action: Action, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(action)
        combos[action] = combo
        handlers[action] = handler
        return activate(action)
    }

    func unregister(_ action: Action) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    /// Temporarily releases every shortcut, e.g. while the user records a new one.
    func suspendAll() {
        for action in Array(refs.keys) { unregister(action) }
    }

    func resumeAll() {
        for action in combos.keys where refs[action] == nil { _ = activate(action) }
    }

    private func activate(_ action: Action) -> Bool {
        guard let combo = combos[action] else { return false }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[action] = ref
        return true
    }

    fileprivate func fire(_ id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        handlers[action]?()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotkeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
