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

/// Per-provider menu-bar text settings. Keys: `<namespace>.menuBarDigitWidth`,
/// `<namespace>.menuBarDigitSize`.
@MainActor
@Observable
final class MenuBarTextPreferences {
    var width: MenuBarDigitWidth {
        didSet { defaults.set(width.rawValue, forKey: keys.width) }
    }

    var size: MenuBarDigitSize {
        didSet { defaults.set(size.rawValue, forKey: keys.size) }
    }

    /// The proportional system font at the chosen width and size.
    var font: NSFont {
        NSFont.systemFont(ofSize: size.pointSize, weight: .regular, width: width.fontWidth)
    }

    private let defaults: UserDefaults
    private let keys: Keys

    private struct Keys {
        let width: String
        let size: String

        init(namespace: String) {
            width = "\(namespace).menuBarDigitWidth"
            size = "\(namespace).menuBarDigitSize"
        }
    }

    init(namespace: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keys = Keys(namespace: namespace)
        width = defaults.string(forKey: keys.width).flatMap(MenuBarDigitWidth.init(rawValue:)) ?? .normal
        size = defaults.string(forKey: keys.size).flatMap(MenuBarDigitSize.init(rawValue:)) ?? .regular
    }
}
