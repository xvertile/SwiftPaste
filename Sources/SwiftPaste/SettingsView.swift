import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: ClipboardStore

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            HistorySettings(settings: settings, store: store)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            AboutPane(settings: settings, store: store)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 430)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: Settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Open the history with", selection: $settings.hotKeyModifier) {
                    ForEach(HotKeyModifier.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text(settings.hotKeyModifier == .disabled
                     ? "Click the menu bar icon to open the history."
                     : "Tap \(settings.hotKeyModifier.symbol) twice, quickly. Holding it, or using it with another key, is ignored.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Shortcut")
            }

            Section {
                Picker("When you pick an entry", selection: $settings.pasteBehaviour) {
                    ForEach(PasteBehaviour.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)

                Toggle("Paste files as plain text paths", isOn: $settings.pastePlainText)
                Toggle("⌥⌘V pastes the previous entry", isOn: $settings.quickPastePrevious)
                Text("Sends the entry before the current one straight into the app you're in. Press it again to swap back.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Pasting")
            }

            Section {
                Toggle("Show the app each entry came from", isOn: $settings.showSourceApp)
                Toggle("Open Swift Paste at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Appearance & startup")
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            loginError = nil
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - History

private struct HistorySettings: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: ClipboardStore
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep an unlimited number of entries", isOn: $settings.unlimitedItems)

                HStack {
                    Text("Keep at most")
                    TextField("", value: $settings.maxItems, format: .number)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $settings.maxItems, in: Settings.itemCountRange, step: 25)
                        .labelsHidden()
                    Text("entries")
                    Spacer()
                }
                .disabled(settings.unlimitedItems)
                .foregroundStyle(settings.unlimitedItems ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))

                Picker("Remove entries older than", selection: $settings.expiry) {
                    ForEach(ExpiryOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Retention")
            } footer: {
                Text("Pinned entries never expire and are never trimmed. Both rules apply together: an entry goes when it is older than the expiry, or once newer entries push it past the limit.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Section {
                Toggle("Capture images", isOn: $settings.captureImages)
                Text("Passwords marked confidential by password managers are always ignored.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } header: {
                Text("What gets captured")
            }

            Section {
                LabeledContent("Stored") {
                    Text("\(store.items.count) entries · \(store.items.filter(\.pinned).count) pinned")
                }
                HStack {
                    Button("Apply Rules Now") { store.applyRetention() }
                    Spacer()
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                }
            } header: {
                Text("Now")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { store.clearUnpinned() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned entries are kept. This can't be undone.")
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: ClipboardStore

    private let shortcuts: [(String, String)] = [
        ("↩", "Paste the highlighted entry"),
        ("← →", "Switch type filter"),
        ("⌥↩", "Paste as plain text"),
        ("⌥⌘V", "Paste the previous entry (global)"),
        ("⌘,", "Settings"),
        ("⌘1 – ⌘9", "Paste by position"),
        ("space", "Preview"),
        ("⌘C", "Copy without pasting"),
        ("⌫", "Delete"),
        ("⌘P", "Pin or unpin"),
        ("esc", "Close")
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 68, height: 68)
                Text("Swift Paste")
                    .font(.system(size: 16, weight: .semibold))
                Text("Version \(AppAssets.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Clipboard history for macOS · \(settings.shortcutDescription)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Shortcuts")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    ForEach(shortcuts, id: \.0) { key, label in
                        HStack(spacing: 10) {
                            Text(key)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .frame(width: 68, alignment: .leading)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 5)
                                .background(Color.primary.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 4))
                            Text(label)
                                .font(.system(size: 11.5))
                            Spacer()
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Text("\(store.items.count) entries stored")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("View on GitHub") {
                    NSWorkspace.shared.open(AppAssets.repositoryURL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: Settings
    private let store: ClipboardStore

    init(settings: Settings, store: ClipboardStore) {
        self.settings = settings
        self.store = store
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Swift Paste Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
