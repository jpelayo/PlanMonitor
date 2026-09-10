import AppKit
import Foundation

/// How wide the digits in the menu bar are drawn. Maps onto the system font's width axis.
nonisolated enum MenuBarDigitWidth: String, CaseIterable, Sendable {
    case veryNarrow
    case narrow
    case normal
    case wide

    var fontWidth: NSFont.Width {
        switch self {
        case .veryNarrow: .compressed
        case .narrow: .condensed
        case .normal: .standard
        case .wide: .expanded
        }
    }

    var displayName: String {
        switch self {
        case .veryNarrow: String(localized: "Very narrow")
        case .narrow: String(localized: "Narrow")
        case .normal: String(localized: "Normal")
        case .wide: String(localized: "Wide")
        }
    }
}

/// Point size of the digits in the menu bar.
nonisolated enum MenuBarDigitSize: String, CaseIterable, Sendable {
    case verySmall
    case small
    case regular
    case large

    var pointSize: CGFloat {
        switch self {
        case .verySmall: 10
        case .small: 11.5
        case .regular: NSFont.systemFontSize
        case .large: 15
        }
    }

    var displayName: String {
        switch self {
        case .verySmall: String(localized: "Very small")
        case .small: String(localized: "Small")
        case .regular: String(localized: "Regular")
        case .large: String(localized: "Large")
        }
    }
}

/// What a provider's menu-bar digits show. Honoured by providers that have both a 5-hour and a
/// weekly window; OpenRouter has its own money-shaped picker and does not use this.
nonisolated enum MenuBarUsageDisplay: String, CaseIterable, Sendable {
    case fiveHour
    case week
    case both

    var displayName: String {
        switch self {
        case .fiveHour: String(localized: "5-hour usage")
        case .week: String(localized: "Weekly usage")
        case .both: String(localized: "Both")
        }
    }
}

/// Which window fills the ring around a provider's menu-bar glyph, or `off` to leave it whole.
///
/// `off` is the ring every provider drew before this setting existed — `variableValue: nil` and
/// `1.0` render identically, so `off` is the untouched icon, not a special case.
nonisolated enum MenuBarRingSource: String, CaseIterable, Sendable {
    case off
    case fiveHour
    case week

    var displayName: String {
        switch self {
        case .off: String(localized: "Disabled")
        case .fiveHour: String(localized: "5-hour usage")
        case .week: String(localized: "Weekly usage")
        }
    }
}

/// Whether the ring fills with what is left or with what has been spent.
nonisolated enum MenuBarRingSense: String, CaseIterable, Sendable {
    case remaining
    case used

    var displayName: String {
        switch self {
        case .remaining: String(localized: "Remaining")
        case .used: String(localized: "Used")
        }
    }
}

/// Per-provider menu-bar text settings. Keys: `<namespace>.menuBarUsageDisplay`,
/// `<namespace>.menuBarDigitWidth`, `<namespace>.menuBarDigitSize`,
/// `<namespace>.menuBarRingSource`, `<namespace>.menuBarRingSense`.
@MainActor
@Observable
final class MenuBarTextPreferences {
    var usageDisplay: MenuBarUsageDisplay {
        didSet { defaults.set(usageDisplay.rawValue, forKey: keys.usageDisplay) }
    }

    var width: MenuBarDigitWidth {
        didSet { defaults.set(width.rawValue, forKey: keys.width) }
    }

    var size: MenuBarDigitSize {
        didSet { defaults.set(size.rawValue, forKey: keys.size) }
    }

    var ringSource: MenuBarRingSource {
        didSet { defaults.set(ringSource.rawValue, forKey: keys.ringSource) }
    }

    var ringSense: MenuBarRingSense {
        didSet { defaults.set(ringSense.rawValue, forKey: keys.ringSense) }
    }

    /// The proportional system font at the chosen width and size.
    var font: NSFont {
        NSFont.systemFont(ofSize: size.pointSize, weight: .regular, width: width.fontWidth)
    }

    private let defaults: UserDefaults
    private let keys: Keys

    private struct Keys {
        let usageDisplay: String
        let width: String
        let size: String
        let ringSource: String
        let ringSense: String

        init(namespace: String) {
            usageDisplay = "\(namespace).menuBarUsageDisplay"
            width = "\(namespace).menuBarDigitWidth"
            size = "\(namespace).menuBarDigitSize"
            ringSource = "\(namespace).menuBarRingSource"
            ringSense = "\(namespace).menuBarRingSense"
        }
    }

    init(namespace: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keys = Keys(namespace: namespace)
        usageDisplay = defaults.string(forKey: keys.usageDisplay)
            .flatMap(MenuBarUsageDisplay.init(rawValue:)) ?? .fiveHour
        width = defaults.string(forKey: keys.width).flatMap(MenuBarDigitWidth.init(rawValue:)) ?? .normal
        size = defaults.string(forKey: keys.size).flatMap(MenuBarDigitSize.init(rawValue:)) ?? .regular
        ringSource = defaults.string(forKey: keys.ringSource)
            .flatMap(MenuBarRingSource.init(rawValue:)) ?? .off
        ringSense = defaults.string(forKey: keys.ringSense)
            .flatMap(MenuBarRingSense.init(rawValue:)) ?? .remaining
    }
}
