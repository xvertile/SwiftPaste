import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless panel that still accepts keyboard focus.
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows the history popup at the cursor and pastes into the previously focused app.
@MainActor
final class PopupController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let model: HistoryViewModel
    private var panel: PopupPanel?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var previewClickMonitor: Any?
    /// True once the user has clicked into the preview to select text; while it holds,
    /// the list must not grab the keyboard back.
    private var previewHoldsFocus = false
    private weak var previousApp: NSRunningApplication?
    private lazy var preview = PreviewController(store: store)

    private let panelSize = NSSize(width: 400, height: 480)

    init(store: ClipboardStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        self.model = HistoryViewModel(store: store)
        super.init()
        model.onPaste = { [weak self] item in self?.paste(item) }
        model.onClose = { [weak self] in self?.hide() }
        model.onPreview = { [weak self] item in self?.togglePreview(item) }
        model.onSelectionChanged = { [weak self] item in
            self?.preview.update(item)
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        let panel = panel ?? makePanel()
        self.panel = panel

        model.prepareForDisplay()
        panel.setFrame(frameAtCursor(), display: false)

        // Deliberately no NSApp.activate: a non-activating panel takes keyboard input
        // without switching the active app, so the caret stays where the user left it.
        panel.orderFrontRegardless()
        panel.makeKey()
        installKeyMonitor()
        installClickMonitor()
    }

    func hide() {
        removeKeyMonitor()
        removeClickMonitor()
        preview.close()
        panel?.orderOut(nil)

        // Only needed if something did pull activation over to us.
        let us = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == us,
           let previousApp, !previousApp.isTerminated {
            previousApp.activate(options: [])
        }
    }

    // MARK: - Panel

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let host = NSHostingView(rootView: HistoryView(model: model, store: store))
        host.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = host
        return panel
    }

    /// Anchors the popup below-right of the pointer, nudged to stay on screen.
    private func frameAtCursor() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: mouse.x + 8, y: mouse.y - panelSize.height - 8)
        if origin.x + panelSize.width > visible.maxX { origin.x = mouse.x - panelSize.width - 8 }
        if origin.x < visible.minX { origin.x = visible.minX + 8 }
        if origin.y < visible.minY { origin.y = min(mouse.y + 8, visible.maxY - panelSize.height - 8) }
        if origin.y + panelSize.height > visible.maxY { origin.y = visible.maxY - panelSize.height - 8 }
        if origin.y < visible.minY { origin.y = visible.minY + 8 }

        return NSRect(origin: origin, size: panelSize)
    }

    /// A non-activating panel loses key status for all sorts of incidental reasons while the
    /// app underneath stays frontmost — moving the pointer over its windows, opening the
    /// preview, starting a drag. Losing key is therefore *not* treated as "dismiss me";
    /// clicks outside the app do that instead. Here we simply take the keyboard back so
    /// Esc and the arrows keep working wherever the pointer happens to be.
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            guard !self.previewHoldsFocus, !self.preview.isKey else { return }
            guard NSApp.keyWindow !== self.panel else { return }
            self.panel?.makeKey()
        }
    }

    private func togglePreview(_ item: ClipboardItem) {
        guard let panel else { return }
        preview.toggle(item, attachedTo: panel)
        previewHoldsFocus = false
        // Keyboard control belongs to the list, so Esc and the arrows keep working.
        panel.makeKey()
    }

    // MARK: - Paste

    private func paste(_ item: ClipboardItem) {
        monitor.acknowledgeOwnWrite()
        Paster.writeToPasteboard(item, store: store)
        monitor.acknowledgeOwnWrite()

        let target = previousApp
        hide()
        // Reorder only once the list is off screen, otherwise the row jumps under the
        // pointer while it is still being looked at.
        store.touch(item)

        guard AXIsProcessTrusted() else {
            warnAboutMissingPermissionOnce()
            return
        }

        // The panel just gave up key status; let the target app take focus back before
        // the keystroke lands, otherwise it is delivered to nothing.
        if let target, !target.isTerminated, !target.isActive {
            target.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.sendCommandV()
        }
    }

    private var warnedAboutPermission = false

    /// Without Accessibility we can still put the item on the clipboard — say so rather than
    /// appearing to do nothing.
    private func warnAboutMissingPermissionOnce() {
        guard !warnedAboutPermission else { return }
        warnedAboutPermission = true

        let alert = NSAlert()
        alert.messageText = "Copied — but auto-paste needs permission"
        alert.informativeText = """
        The item is on your clipboard, so ⌘V works right now.

        To have Swift Paste paste for you, enable it in \
        System Settings › Privacy & Security › Accessibility.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Global mouse events only arrive for clicks in *other* apps, which is exactly the
    /// gesture that should dismiss the list. Clicks on our own panels stay local.
    private func installClickMonitor() {
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            }
        }

        // Clicking into the preview means the user wants to select and copy text. Selection
        // needs a real first responder, which a background app's panel cannot have — so
        // this is the one gesture that earns activation.
        if previewClickMonitor == nil {
            previewClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self, self.preview.owns(event.window) else { return event }
                self.previewHoldsFocus = true
                NSApp.activate(ignoringOtherApps: true)
                self.preview.makeKey()
                return event
            }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let previewClickMonitor { NSEvent.removeMonitor(previewClickMonitor) }
        previewClickMonitor = nil
        previewHoldsFocus = false
    }

    /// Returns true when the event was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        let command = event.modifierFlags.contains(.command)

        // Space previews the highlighted entry, the way Finder does. The search field also
        // wants Space, so it only previews while the field is empty; ⌘Y always works.
        if Int(event.keyCode) == kVK_Space, model.query.isEmpty, !event.modifierFlags.contains(.command) {
            model.previewSelected()
            return true
        }
        if command, Int(event.keyCode) == kVK_ANSI_Y {
            model.previewSelected()
            return true
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            if preview.isVisible {
                preview.close()
                previewHoldsFocus = false
                panel?.makeKey()   // the preview may have held focus for text selection
                return true
            }
            hide()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.pasteSelected()
            return true
        case kVK_DownArrow:
            model.moveSelection(by: 1)
            return true
        case kVK_UpArrow:
            model.moveSelection(by: -1)
            return true
        case kVK_PageDown:
            model.moveSelection(by: 8)
            return true
        case kVK_PageUp:
            model.moveSelection(by: -8)
            return true
        case kVK_Home:
            model.selectEdge(first: true)
            return true
        case kVK_End:
            model.selectEdge(first: false)
            return true
        // ⌘⌫ always deletes; a bare ⌫ deletes too while the search field is empty and so
        // has nothing to erase.
        case kVK_Delete where command || model.query.isEmpty,
             kVK_ForwardDelete:
            model.deleteSelected()
            return true
        case kVK_ANSI_P where command:
            model.togglePinSelected()
            return true
        default:
            break
        }

        if command, let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }), (1...9).contains(digit) {
            model.paste(at: digit - 1)
            return true
        }
        return false
    }
}
