import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's hot keys, which need no permission. A shortcut
/// exists only while registered: unregistering removes it from the system.
@MainActor
final class HotKeyCenter {
    enum Event {
        case pressed
        case released
    }

    private static let signature: OSType = 0x4753_5456 // "GSTV"

    private var handlerRef: EventHandlerRef?
    private var hotKeys: [UInt32: (ref: EventHotKeyRef, action: (Event) -> Void)] = [:]
    private var nextID: UInt32 = 1

    /// Returns an id for `unregister`, or nil when the system refused the shortcut, for
    /// example because another app holds it.
    func register(keyCode: Int, modifiers: Int, action: @escaping (Event) -> Void) -> UInt32? {
        // Without the handler the shortcut would exist system-wide with its presses dropped.
        guard installHandlerIfNeeded() else { return nil }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            removeHandlerIfUnused()
            return nil
        }
        hotKeys[id] = (ref, action)
        return id
    }

    func unregister(_ id: UInt32) {
        guard let entry = hotKeys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
        removeHandlerIfUnused()
    }

    private func removeHandlerIfUnused() {
        guard hotKeys.isEmpty, let handlerRef else { return }
        RemoveEventHandler(handlerRef)
        self.handlerRef = nil
    }

    fileprivate func handle(id: UInt32, kind: UInt32) {
        hotKeys[id]?.action(kind == UInt32(kEventHotKeyPressed) ? .pressed : .released)
    }

    private func installHandlerIfNeeded() -> Bool {
        guard handlerRef == nil else { return true }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(), hotKeyHandler, types.count, &types,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr, handlerRef != nil else {
            handlerRef = nil
            return false
        }
        return true
    }
}

private func hotKeyHandler(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let kind = GetEventKind(event)
    // Carbon delivers hot key events on the main thread.
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { center.handle(id: hotKeyID.id, kind: kind) }
    return noErr
}
