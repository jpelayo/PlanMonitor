import AppKit
import SwiftUI

/// Claude-API's menu-bar label, on OpenRouter's two-channel design:
///   icon → the tighter of promotional credit and spend, used against what bounds it (strategic)
///   text → whatever the user picked, tinted by the used fraction of what it shows (tactical)
///
/// The glyph is `eurosign.ring.dashed`, chosen for its letterform beside Claude's `₵`, Grok's `₲`
/// and OpenRouter's `$` — not as a statement about currency. The amounts stay in their own.
enum ClaudePlatformMenuBarLabel {
    static func make(
        snapshot: ClaudePlatformSnapshot,
        authState: ClaudePlatformAuthState,
        display: ClaudePlatformMenuBarDisplay,
        currencyStyle: CurrencyStyle,
        ringFill: Double?,
        font: NSFont
    ) -> MenuBarLabel {
        let digits = authState.isAuthenticated
            ? ClaudePlatformMenuBarDigits.resolve(display: display, figures: snapshot.figures, style: currencyStyle)
            : ClaudePlatformMenuBarDigits.Resolved(text: nil, severityFraction: nil)
        let headroom = authState.isAuthenticated
            ? [snapshot.promoUsedFraction, snapshot.spendUsedFraction].compactMap { $0 }.max()
            : nil

        return MenuBarLabel(
            symbolName: "eurosign.ring.dashed",
            fallbackSymbol: "ring.dashed",
            // From the view model's `ringSource`; `nil` leaves the ring whole.
            variableValue: ringFill,
            symbolTint: ClaudePlatformSeverity(headroom).iconTint,
            text: digits.text,
            textTint: digits.text == nil ? nil : ClaudePlatformSeverity(digits.severityFraction).tint,
            font: font,
            accessibilityLabel: String(localized: "PlanMonitor for Claude-API"),
            accessibilityValue: digits.text ?? String(localized: "Not signed in")
        )
    }
}

/// `BudgetSeverity`, copied and renamed rather than shared: one module is one namespace, and the
/// OpenRouter type stays where it is (plan §3.2). Thresholds on a *used* fraction.
nonisolated enum ClaudePlatformSeverity: Equatable, Sendable {
    case normal
    case warning
    case critical

    init(_ usedFraction: Double?) {
        guard let usedFraction else { self = .normal; return }
        switch usedFraction {
        case ..<0.65: self = .normal
        case 0.65..<0.90: self = .warning
        default: self = .critical
        }
    }

    /// For the digits: nil means "no tint" — the adaptive grey, correct for normal.
    var tint: NSColor? {
        switch self {
        case .normal: nil
        case .warning: Self.warningColor
        case .critical: .systemRed
        }
    }

    /// For the menu-bar glyph: always coloured, matching the gauges in the dropdown.
    var iconTint: NSColor {
        switch self {
        case .normal: .systemGreen
        case .warning: Self.warningColor
        case .critical: .systemRed
        }
    }

    nonisolated static let warningColor = NSColor(srgbRed: 0.82, green: 0.42, blue: 0.04, alpha: 1)

    var color: Color {
        switch self {
        case .normal: .green
        case .warning: Color(red: 0.82, green: 0.42, blue: 0.04)
        case .critical: .red
        }
    }
}
