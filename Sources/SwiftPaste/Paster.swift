import AppKit
import Carbon.HIToolbox
import Foundation

enum Paster {
    /// Replaces the pasteboard contents with the item's payload.
    @MainActor
    static func writeToPasteboard(_ item: ClipboardItem, store: ClipboardStore, plainTextOnly: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .text:
            pb.setString(item.text, forType: .string)
        case .files:
            let urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            if urls.isEmpty {
                pb.setString(item.text, forType: .string)
            } else if plainTextOnly {
                pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            } else {
                pb.writeObjects(urls as [NSURL])
                pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            }
        case .image:
            guard let url = store.imageURL(for: item), let data = try? Data(contentsOf: url) else { return }
            pb.setData(data, forType: .png)
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
    }

    /// Synthesises ⌘V for whichever app is frontmost.
    @discardableResult
    static func sendCommandV() -> Bool {
        guard AXIsProcessTrusted() else {
            NSLog("[SwiftPaste] paste skipped: not trusted for Accessibility")
            return false
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            NSLog("[SwiftPaste] paste failed: no CGEventSource")
            return false
        }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            NSLog("[SwiftPaste] paste failed: could not create key events")
            return false
        }
        // Exactly ⌘ — any modifier the user is still physically holding must not leak in,
        // or the target app sees ⌥⌘V / ⇧⌘V instead of a plain paste.
        down.flags = .maskCommand
        up.flags = .maskCommand

        // The annotated session tap delivers to the focused app of this login session,
        // which is more reliable here than the HID tap.
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
