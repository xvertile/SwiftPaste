import AppKit
import Carbon.HIToolbox

/// The action for the single Carbon hot key this app registers. Written and read on the
/// main thread only; the C callback hops there before touching it.
private var registeredAction: (() -> Void)?

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async { registeredAction?() }
    return noErr
}

/// A conventional system-wide chord, registered through Carbon so the keystroke is
/// *consumed* — an `NSEvent` global monitor can only observe, which would let the
/// frontmost app act on the same shortcut.
///
/// Unlike the double-tap shortcut this needs no Accessibility permission to fire; only the
/// synthetic ⌘V it triggers does.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var isRegistered: Bool { hotKeyRef != nil }

    /// - Parameters:
    ///   - keyCode: a `kVK_` virtual key code.
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(cmdKey | optionKey)`.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        unregister()
        registeredAction = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &handlerRef
        )
        guard installed == noErr else {
            registeredAction = nil
            return false
        }

        // 'SWPT' — any four-character code will do, it just has to be ours.
        let hotKeyID = EventHotKeyID(signature: OSType(0x53_57_50_54), id: 1)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        registeredAction = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
