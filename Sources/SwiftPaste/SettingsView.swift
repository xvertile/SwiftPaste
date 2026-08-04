import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: ClipboardStore

    var body: some View {
        Form {
            Section {
                Toggle("Keep an unlimited number of entries", isOn: $settings.unlimitedItems)

                HStack {
                    Text("Keep at most")
                    TextField(
                        "",
                        value: $settings.maxItems,
                        format: .number
                    )
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                    Stepper("", value: $settings.maxItems, in: 5...10_000, step: 25)
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
                Text("Pinned entries are never trimmed or expired. Both rules apply together: an entry goes away when it is older than the expiry, or once newer entries push it past the limit.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Section("Now") {
                LabeledContent("Stored") {
                    Text("\(store.items.count) entries · \(store.items.filter(\.pinned).count) pinned")
                }
                HStack {
                    Spacer()
                    Button("Apply Now") { store.applyRetention() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

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
