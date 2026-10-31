import Carbon.HIToolbox
import ShellCore

/// Global shortcut via Carbon; needs no accessibility permission.
@MainActor
public final class HotKeyCenter: HotKeyRegistering {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    fileprivate var handler: (@MainActor () -> Void)?

    public init() {}

    public func register(_ hotKey: HotKey, handler: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        self.handler = handler

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { center.handler?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let status = RegisterEventHotKey(
            hotKey.keyCode, hotKey.modifiers.carbon, EventHotKeyID(signature: OSType(0x4F52_4254), id: 1),
            GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { unregister() }
        return status == noErr
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        handler = nil
    }
}

extension HotKey.Modifiers {
    fileprivate var carbon: UInt32 {
        var value = 0
        if contains(.control) { value |= controlKey }
        if contains(.option) { value |= optionKey }
        if contains(.shift) { value |= shiftKey }
        if contains(.command) { value |= cmdKey }
        return UInt32(value)
    }
}
