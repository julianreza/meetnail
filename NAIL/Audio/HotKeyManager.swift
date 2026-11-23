import Carbon
import Foundation

@MainActor
final class HotKeyManager {
    private final class Registration: @unchecked Sendable {
        var hotKeyRef: EventHotKeyRef?
        var handlerRef: EventHandlerRef?

        deinit {
            if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
            if let handlerRef { RemoveEventHandler(handlerRef) }
        }
    }

    private let registration = Registration()
    private let onInterrupt: @MainActor @Sendable () -> Void

    init(onInterrupt: @escaping @MainActor @Sendable () -> Void) {
        self.onInterrupt = onInterrupt
        register()
    }

    private func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onInterrupt()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handler
        )
        guard status == noErr else { return }
        registration.handlerRef = handler

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E41494C), id: 1) // "NAIL"
        var hotKey: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        registration.hotKeyRef = hotKey
    }
}
