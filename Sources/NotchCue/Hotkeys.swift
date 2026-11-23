import Carbon.HIToolbox

/// Global shortcuts through Carbon hot keys: they work in every app and need no Accessibility
/// or Input Monitoring permission. Both key-down and key-up are reported, for hold-to-scroll.
@MainActor
final class Hotkeys {
    enum Action: UInt32 {
        case toggle = 1, restart, showHide, hold
    }

    static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    static let holdKeyCode = UInt16(kVK_DownArrow)

    private let onEvent: (Action, _ pressed: Bool) -> Void
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(onEvent: @escaping (Action, Bool) -> Void) {
        self.onEvent = onEvent
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotkeys.handle(id.id, pressed: pressed) }
            return noErr
        }, specs.count, &specs, me, &handler)

        register(.toggle, keyCode: kVK_ANSI_P)
        register(.restart, keyCode: kVK_ANSI_R)
        register(.showHide, keyCode: kVK_ANSI_H)
        register(.hold, keyCode: kVK_DownArrow)
    }

    /// True while the hold key is physically down. Used as a failsafe in case a release event is missed.
    static var holdKeyIsDown: Bool {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(holdKeyCode))
    }

    private func register(_ action: Action, keyCode: Int) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4E43_4B59), id: action.rawValue) // "NCKY"
        let status = RegisterEventHotKey(UInt32(keyCode), Self.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) } else {
            speechLog.error("hotkey \(action.rawValue) not registered: \(status)")
        }
    }

    private func handle(_ id: UInt32, pressed: Bool) {
        guard let action = Action(rawValue: id) else { return }
        if action != .hold, !pressed { return }
        onEvent(action, pressed)
    }
}
