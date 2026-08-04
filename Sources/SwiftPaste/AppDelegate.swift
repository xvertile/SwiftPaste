import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private lazy var store = ClipboardStore(settings: settings)
    private var monitor: ClipboardMonitor!
    private var popup: PopupController!
    private var hotKey: DoubleTapHotKey!
    private var settingsWindow: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var permissionTimer: Timer?
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()
        settings.onRetentionChange = { [weak self] in self?.store.applyRetention() }

        monitor = ClipboardMonitor(store: store)
        popup = PopupController(store: store, monitor: monitor)
        hotKey = DoubleTapHotKey(flag: .option) { [weak self] in self?.popup.toggle() }
        settingsWindow = SettingsWindowController(settings: settings, store: store)

        setupStatusItem()
        monitor.start()
        hotKey.start()
        startRetentionSweep()
        NSLog("[SwiftPaste] launched — accessibility trusted: %@, %d items",
              AXIsProcessTrusted() ? "yes" : "no", store.items.count)

        if !AXIsProcessTrusted() {
            // Non-blocking system prompt; the menu keeps a warning item until it's granted.
            requestAccessibility()
            watchForAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        hotKey.stop()
        monitor.stop()
        permissionTimer?.invalidate()
        retentionTimer?.invalidate()
    }

    /// Time-based expiry needs a heartbeat; entries can age out while nothing is copied.
    private func startRetentionSweep() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.applyRetention() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarImage()
            button.toolTip = "Swift Paste — tap ⌥ twice"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menu = NSMenu()
        menu.delegate = self
        rebuildMenu(menu)
    }

    /// The ⌘V logo, drawn as a template so it follows the menu bar's light/dark tint.
    /// Falls back to a system symbol if the resource is missing.
    private static func menuBarImage() -> NSImage? {
        let image: NSImage?
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let logo = NSImage(contentsOf: url) {
            logo.size = NSSize(width: 18, height: 18)
            image = logo
        } else {
            image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Swift Paste")
        }
        image?.isTemplate = true
        image?.accessibilityDescription = "Swift Paste"
        return image
    }

    /// Left click opens the history, right click (or ⌃click) opens the menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true

        if wantsMenu {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            popup.toggle()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: "Open Swift Paste", action: #selector(openPopup), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let hint = NSMenuItem(title: "Tap ⌥ Option twice, or click the icon", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())

        let count = NSMenuItem(title: retentionSummary(), action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)

        if !AXIsProcessTrusted() {
            let permission = NSMenuItem(
                title: "⚠︎ Grant Accessibility Access…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            permission.target = self
            menu.addItem(permission)
        }

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let quit = NSMenuItem(title: "Quit Swift Paste", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// e.g. "42 entries · keeping 300 · expiring after 1 week"
    private func retentionSummary() -> String {
        var parts = ["\(store.items.count) entries"]
        parts.append(settings.unlimitedItems ? "no limit" : "keeping \(settings.maxItems)")
        if settings.expiry != .never {
            parts.append("expiring after \(settings.expiry.label)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    @objc private func openPopup() {
        popup.show()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            presentAlert(
                title: "Couldn't change the login item",
                message: error.localizedDescription
            )
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned items are kept. This can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearUnpinned()
        }
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibility()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        watchForAccessibility()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Permissions

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Global monitors only deliver events once the app is trusted, so re-arm them after the grant.
    private func watchForAccessibility() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.permissionTimer = nil
                self?.hotKey.stop()
                self?.hotKey.start()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
