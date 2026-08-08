import AppKit
import Foundation

/// How long an entry is allowed to sit in the history before it's swept away.
enum ExpiryOption: Int, CaseIterable, Identifiable {
    case never = 0
    case hour = 3_600
    case sixHours = 21_600
    case day = 86_400
    case threeDays = 259_200
    case week = 604_800
    case twoWeeks = 1_209_600
    case month = 2_592_000
    case threeMonths = 7_776_000
    case year = 31_536_000

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never: return "Never"
        case .hour: return "1 hour"
        case .sixHours: return "6 hours"
        case .day: return "1 day"
        case .threeDays: return "3 days"
        case .week: return "1 week"
        case .twoWeeks: return "2 weeks"
        case .month: return "1 month"
        case .threeMonths: return "3 months"
        case .year: return "1 year"
        }
    }

    var seconds: TimeInterval? { self == .never ? nil : TimeInterval(rawValue) }
}

/// The modifier you tap twice to open the history.
enum HotKeyModifier: String, CaseIterable, Identifiable {
    case option
    case command
    case control
    case shift
    case disabled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        case .disabled: return "Disabled"
        }
    }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        case .shift: return "⇧"
        case .disabled: return "—"
        }
    }

    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .option: return .option
        case .command: return .command
        case .control: return .control
        case .shift: return .shift
        case .disabled: return nil
        }
    }
}

/// What happens when you pick an entry.
enum PasteBehaviour: String, CaseIterable, Identifiable {
    case pasteIntoApp
    case copyOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pasteIntoApp: return "Paste it into the app I was using"
        case .copyOnly: return "Just put it on the clipboard"
        }
    }
}

@MainActor
final class Settings: ObservableObject {
    private enum Key {
        static let maxItems = "maxItems"
        static let expiry = "expirySeconds"
        static let unlimited = "unlimitedItems"
        static let hotKey = "hotKeyModifier"
        static let pasteBehaviour = "pasteBehaviour"
        static let plainText = "pastePlainText"
        static let captureImages = "captureImages"
        static let showSourceApp = "showSourceApp"
        static let quickPaste = "quickPastePrevious"
    }

    /// Called when a retention setting changes, so the store can re-apply it right away.
    var onRetentionChange: (() -> Void)?
    /// Called when the shortcut changes, so the hot key can be re-armed.
    var onHotKeyChange: (() -> Void)?

    // MARK: - Retention

    /// Range accepted by the settings field.
    static let itemCountRange = 5...10_000

    @Published var maxItems: Int {
        didSet {
            // Clamp by re-assigning *only* when out of range. An unconditional assignment
            // here re-enters didSet forever — @Published routes it through the wrapper's
            // setter, so Swift's usual same-property recursion guard does not apply.
            let clamped = min(max(maxItems, Self.itemCountRange.lowerBound),
                              Self.itemCountRange.upperBound)
            if maxItems != clamped {
                maxItems = clamped      // re-enters once, then takes the branch below
                return
            }
            guard maxItems != oldValue else { return }
            defaults.set(maxItems, forKey: Key.maxItems)
            notifyRetentionChanged()
        }
    }

    /// When true the entry count is uncapped and only the expiry rule applies.
    @Published var unlimitedItems: Bool {
        didSet {
            guard unlimitedItems != oldValue else { return }
            defaults.set(unlimitedItems, forKey: Key.unlimited)
            notifyRetentionChanged()
        }
    }

    @Published var expiry: ExpiryOption {
        didSet {
            guard expiry != oldValue else { return }
            defaults.set(expiry.rawValue, forKey: Key.expiry)
            notifyRetentionChanged()
        }
    }

    // MARK: - Behaviour

    @Published var hotKeyModifier: HotKeyModifier {
        didSet {
            guard hotKeyModifier != oldValue else { return }
            defaults.set(hotKeyModifier.rawValue, forKey: Key.hotKey)
            onHotKeyChange?()
        }
    }

    @Published var pasteBehaviour: PasteBehaviour {
        didSet {
            guard pasteBehaviour != oldValue else { return }
            defaults.set(pasteBehaviour.rawValue, forKey: Key.pasteBehaviour)
        }
    }

    @Published var pastePlainText: Bool {
        didSet { defaults.set(pastePlainText, forKey: Key.plainText) }
    }

    @Published var captureImages: Bool {
        didSet { defaults.set(captureImages, forKey: Key.captureImages) }
    }

    @Published var showSourceApp: Bool {
        didSet { defaults.set(showSourceApp, forKey: Key.showSourceApp) }
    }

    /// ⌥⌘V pastes the entry before the current one, without opening the list.
    @Published var quickPastePrevious: Bool {
        didSet {
            guard quickPastePrevious != oldValue else { return }
            defaults.set(quickPastePrevious, forKey: Key.quickPaste)
            onHotKeyChange?()
        }
    }

    /// Applying retention mutates the store, which SwiftUI may currently be rendering.
    /// Hopping to the next run loop turn keeps that mutation out of the view update.
    private func notifyRetentionChanged() {
        guard let onRetentionChange else { return }
        DispatchQueue.main.async { onRetentionChange() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.captureImages: true,
            Key.showSourceApp: true,
            Key.quickPaste: true
        ])
        self.defaults = defaults

        let storedMax = defaults.integer(forKey: Key.maxItems)
        maxItems = storedMax == 0 ? 300 : storedMax
        unlimitedItems = defaults.bool(forKey: Key.unlimited)
        expiry = ExpiryOption(rawValue: defaults.integer(forKey: Key.expiry)) ?? .never
        hotKeyModifier = defaults.string(forKey: Key.hotKey)
            .flatMap(HotKeyModifier.init(rawValue:)) ?? .option
        pasteBehaviour = defaults.string(forKey: Key.pasteBehaviour)
            .flatMap(PasteBehaviour.init(rawValue:)) ?? .pasteIntoApp
        pastePlainText = defaults.bool(forKey: Key.plainText)
        captureImages = defaults.bool(forKey: Key.captureImages)
        showSourceApp = defaults.bool(forKey: Key.showSourceApp)
        quickPastePrevious = defaults.bool(forKey: Key.quickPaste)
    }

    /// nil means "keep as many as you like".
    var itemLimit: Int? { unlimitedItems ? nil : maxItems }

    /// e.g. "⌥⌥" — used in the UI to describe the shortcut.
    var shortcutDescription: String {
        hotKeyModifier == .disabled
            ? "Menu bar icon only"
            : "\(hotKeyModifier.symbol)\(hotKeyModifier.symbol)"
    }
}
