import AppKit

/// What a provider wants shown in the menu bar. Providers compute this from their own
/// semantics; the host renders it on an `NSStatusItem`, where AppKit draws the symbol and the
/// digits as real text — adaptive to the bar's appearance, highlighted correctly, readable by
/// VoiceOver, and coloured only when a tint is given.
struct MenuBarLabel: Equatable {
    var symbolName: String
    var fallbackSymbol: String
    var variableValue: Double? = nil
    /// `nil` keeps the system's adaptive menu-bar grey (template rendering).
    var symbolTint: NSColor? = nil
    var text: String? = nil
    /// `nil` keeps the menu bar's own text colour.
    var textTint: NSColor? = nil
    /// Face and size of the digits. Proportional system font at menu-bar size by default;
    /// the status item is variable-length, so any font reflows correctly.
    var font: NSFont = MenuBarLabel.defaultFont
    var accessibilityLabel: String
    var accessibilityValue: String? = nil

    static let defaultPointSize: CGFloat = NSFont.systemFontSize
    static let defaultFont = NSFont.systemFont(ofSize: defaultPointSize, weight: .regular)
    static let symbolPointSize: CGFloat = 15

    var resolvedSymbolName: String {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil ? symbolName : fallbackSymbol
    }
}
