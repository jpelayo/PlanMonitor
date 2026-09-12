import AppKit
import SwiftUI

/// Two independent channels, ported from the Claude variant's design:
///   icon  → account credit health (slow, strategic)
///   text  → worst key/guardrail budget (fast, tactical)
/// A key about to hit its daily cap tints the number without implying the balance is low.
enum OpenRouterMenuBarLabel {
    static func make(
        snapshot: OpenRouterSnapshot,
        connectionState: ConnectionState,
        display: MenuBarDisplay,
        ringFill: Double?,
        font: NSFont
    ) -> MenuBarLabel {
        let text = display == .iconOnly ? nil : valueText(snapshot: snapshot, connectionState: connectionState, display: display)
        return MenuBarLabel(
            symbolName: "dollarsign.ring.dashed",
            fallbackSymbol: "ring.dashed",
            // Computed by the view model from its `ringSource` (credit since top-up, pooled
            // limits, worst budget, or off), because two of those need state the snapshot does
            // not carry. `nil` leaves the ring whole.
            variableValue: ringFill,
            symbolTint: creditSeverity(snapshot: snapshot, connectionState: connectionState).iconTint,
            text: text,
            textTint: text == nil ? nil : budgetSeverity(snapshot: snapshot, connectionState: connectionState).tint,
            font: font,
            accessibilityLabel: String(localized: "OpenRouter credit"),
            accessibilityValue: text ?? String(localized: "Not connected")
        )
    }

    private static func creditSeverity(snapshot: OpenRouterSnapshot, connectionState: ConnectionState) -> BudgetSeverity {
        guard connectionState.showsBudgets, let credit = snapshot.accountCredit else { return .normal }
        return credit.severity
    }

    private static func budgetSeverity(snapshot: OpenRouterSnapshot, connectionState: ConnectionState) -> BudgetSeverity {
        guard connectionState.showsBudgets else { return .normal }
        if snapshot.accountCredit?.isNegative == true { return .critical }
        return BudgetSeverity(snapshot.worstBudgetFraction)
    }

    private static func valueText(
        snapshot: OpenRouterSnapshot,
        connectionState: ConnectionState,
        display: MenuBarDisplay
    ) -> String? {
        guard connectionState.showsBudgets, let credit = snapshot.accountCredit else { return nil }
        switch display {
        case .iconOnly:
            return nil
        case .amount:
            return Money.formatMenuBar(credit.remaining)
        case .percent:
            // Percent of the tightest real budget remaining — not of lifetime credit,
            // which has no denominator worth showing.
            guard let worst = snapshot.worstBudgetFraction else {
                return Money.formatMenuBar(credit.remaining)
            }
            return "\(Int(((1 - worst) * 100).rounded()))%"
        }
    }
}

nonisolated enum BudgetSeverity: Equatable, Sendable {
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
