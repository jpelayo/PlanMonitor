//
//  ClaudeMenuBarIconLabel.swift
//  PlanTracker
//

import AppKit

/// Claude's menu-bar label: the icon's *colour* follows weekly severity, its *ring* follows the
/// window the user picked for it (or stays whole), and the digits follow whichever windows they were
/// pointed at. Rendered by `StatusItemController` as a real AppKit title, never rasterised.
enum ClaudeMenuBarLabel {
    static func make(
        usageData: ClaudeUsageData,
        authState: ClaudeAuthState,
        showRemainingPercent: Bool,
        usageDisplay: MenuBarUsageDisplay,
        ringSource: MenuBarRingSource,
        ringSense: MenuBarRingSense,
        font: NSFont
    ) -> MenuBarLabel {
        let digits = authState.isAuthenticated
            ? MenuBarUsageDigits.resolve(
                display: usageDisplay,
                fiveHour: usageData.fiveHourUtilization,
                // The main 7-day limit only. The model-scoped windows (Opus, Sonnet, and the
                // dynamic one that renders as e.g. "Fable (7-Day)") are never "the week".
                week: usageData.sevenDayUtilization,
                showRemainingPercent: showRemainingPercent
            )
            : MenuBarUsageDigits.Resolved(text: nil, severityUtilization: nil)
        let percentage = digits.text
        return MenuBarLabel(
            symbolName: "cedisign.ring.dashed",
            fallbackSymbol: "ring.dashed",
            variableValue: MenuBarUsageRing.fill(
                source: ringSource,
                sense: ringSense,
                fiveHour: usageData.fiveHourUtilization,
                week: usageData.sevenDayUtilization
            ),
            symbolTint: ClaudeMenuBarUsageSeverity(usageData.sevenDayUtilization).iconTint,
            text: percentage,
            textTint: percentage == nil ? nil : ClaudeMenuBarUsageSeverity(digits.severityUtilization).tint,
            font: font,
            accessibilityLabel: String(localized: "PlanMonitor for Claude"),
            accessibilityValue: percentage ?? String(localized: "Not signed in")
        )
    }
}

enum ClaudeMenuBarUsageSeverity: Equatable {
    case normal
    case warning
    case critical

    init(_ utilization: Double?) {
        guard let utilization else {
            self = .normal
            return
        }
        switch utilization {
        case ..<65: self = .normal
        case 65..<90: self = .warning
        default: self = .critical
        }
    }

    /// For the digits: no colour at normal, so they keep the bar's adaptive grey.
    var tint: NSColor? {
        switch self {
        case .normal: nil
        case .warning: Self.warningColor
        case .critical: .systemRed
        }
    }

    /// For the menu-bar glyph: always coloured, matching the usage bar it stands for.
    /// A colour needs a non-template image, which is why the symbol is rasterised.
    var iconTint: NSColor {
        switch self {
        case .normal: .systemGreen
        case .warning: Self.warningColor
        case .critical: .systemRed
        }
    }

    static let warningColor = NSColor(srgbRed: 0.82, green: 0.42, blue: 0.04, alpha: 1)
}
