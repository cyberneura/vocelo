import Carbon

@MainActor
final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var pressed = false
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private static let signature: OSType = 0x564F434C // VOCL

    func register(config: VoceloConfig) throws {
        if handler == nil {
            var types = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                // Carbon dispatches this application event handler on the main thread.
                return MainActor.assumeIsolated {
                    let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                    var id = EventHotKeyID()
                    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                    guard result == noErr, id.signature == HotKeyManager.signature, id.id == 1 else {
                        return OSStatus(eventNotHandledErr)
                    }
                    switch GetEventKind(event) {
                    case UInt32(kEventHotKeyPressed):
                        if !manager.pressed { manager.pressed = true; manager.onPress?() }
                    case UInt32(kEventHotKeyReleased):
                        if manager.pressed { manager.pressed = false; manager.onRelease?() }
                    default: return OSStatus(eventNotHandledErr)
                    }
                    return noErr
                }
            }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw VoceloError("Cannot install hotkey handler (\(status)).") }
        }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(config.keyCode, config.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr else { throw VoceloError("Cannot register hotkey (\(status)); it may be in use by another app.") }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        pressed = false
    }
}
