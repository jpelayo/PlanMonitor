import AppKit
import SwiftUI

/// OpenCode's menu-bar label:
///   icon → the tightest of the Go windows and the budget, coloured by severity; a rate-limited
///          window or a reached budget is critical
///   text → the Go window the user picked, tinted by its used share
///
/// The glyph is `pesetasign.ring.dashed` (₧, user decision 2026-10-22), unmistakable beside
/// Claude's `₵`, Grok's `₲`, OpenRouter's `$` and Claude-API's `€` — not a statement about currency.
enum OpenCodeMenuBarLabel {
    static let symbolName = "pesetasign.ring.dashed"

    static func make(
        snapshot: OpenCodeSnapshot,
        connectionState: OpenCodeConnectionState,
        display: OpenCodeMenuBarDisplay,
        showRemainingPercent: Bool,
        ringFill: Double?,
        font: NSFont
    ) -> MenuBarLabel {
        let showsBudget = connectionState.showsBudget
        let digits = showsBudget
            ? OpenCodeMenuBarDigits.resolve(display: display, go: snapshot.go, showRemainingPercent: showRemainingPercent)
            : OpenCodeMenuBarDigits.Resolved(text: nil, severityFraction: nil)
        let budgetUsed = snapshot.exceeded ? 1 : snapshot.usedFraction
        let used: Double? = showsBudget
            ? [snapshot.go?.worstUsedFraction, budgetUsed].compactMap { $0 }.max()
            : nil

        return MenuBarLabel(
            symbolName: symbolName,
            fallbackSymbol: "ring.dashed",
            // From the view model's `ringSource`; `nil` leaves the ring whole.
            variableValue: ringFill,
            symbolTint: OpenCodeSeverity(used).iconTint,
            text: digits.text,
            textTint: digits.text == nil ? nil : OpenCodeSeverity(digits.severityFraction).tint,
            font: font,
            accessibilityLabel: String(localized: "PlanMonitor for OpenCode"),
            accessibilityValue: digits.text ?? String(localized: "Not connected")
        )
    }
}

/// `ClaudePlatformSeverity`, copied and renamed rather than shared: one module is one namespace.
/// Thresholds on a *used* fraction.
nonisolated enum OpenCodeSeverity: Equatable, Sendable {
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

    /// For the menu-bar glyph: always coloured, matching the gauge in the dropdown.
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
