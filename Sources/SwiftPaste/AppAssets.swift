import AppKit

/// Bundle artwork plus a small cache of source-app icons.
@MainActor
enum AppAssets {
    /// The ⌘V mark, as a template so it picks up the surrounding text colour.
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return short
    }

    static let repositoryURL = URL(string: "https://github.com/xvertile/SwiftPaste")!

    private static var appIcons: [String: NSImage] = [:]

    /// Icon of the app an entry was copied from, for the little badge on each row.
    static func sourceIcon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }
}
