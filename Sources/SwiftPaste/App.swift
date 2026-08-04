import AppKit

@main
enum SwiftPasteApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        let delegate = AppDelegate()
        app.delegate = delegate
        // Keep the delegate alive for the process lifetime.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
