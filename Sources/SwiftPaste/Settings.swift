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

@MainActor
final class Settings: ObservableObject {
    private enum Key {
        static let maxItems = "maxItems"
        static let expiry = "expirySeconds"
        static let unlimited = "unlimitedItems"
    }

    /// Called whenever a retention setting changes, so the store can re-apply it right away.
    var onRetentionChange: (() -> Void)?

    @Published var maxItems: Int {
        didSet {
            maxItems = min(max(maxItems, 5), 10_000)
            guard maxItems != oldValue else { return }
            defaults.set(maxItems, forKey: Key.maxItems)
            onRetentionChange?()
        }
    }

    /// When true the entry count is uncapped and only the expiry rule applies.
    @Published var unlimitedItems: Bool {
        didSet {
            guard unlimitedItems != oldValue else { return }
            defaults.set(unlimitedItems, forKey: Key.unlimited)
            onRetentionChange?()
        }
    }

    @Published var expiry: ExpiryOption {
        didSet {
            guard expiry != oldValue else { return }
            defaults.set(expiry.rawValue, forKey: Key.expiry)
            onRetentionChange?()
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMax = defaults.integer(forKey: Key.maxItems)
        maxItems = storedMax == 0 ? 300 : storedMax
        unlimitedItems = defaults.bool(forKey: Key.unlimited)
        expiry = ExpiryOption(rawValue: defaults.integer(forKey: Key.expiry)) ?? .never
    }

    /// nil means "keep as many as you like".
    var itemLimit: Int? { unlimitedItems ? nil : maxItems }
}
