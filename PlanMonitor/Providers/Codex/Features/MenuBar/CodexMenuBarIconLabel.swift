//
//  CodexMenuBarIconLabel.swift
//  PlanTracker
//

import AppKit

/// Codex's menu-bar label: weekly severity drives the icon's colour, the user's ring choice drives
/// how full it is drawn, and the digits follow whichever windows they were pointed at — falling back
/// to the remaining API slots when neither of the two named windows is reported.
enum CodexMenuBarLabel {
    static func make(
        usageData: CodexUsageData,
        authState: CodexAuthState,
        showRemainingPercent: Bool,
        usageDisplay: MenuBarUsageDisplay,
        ringSource: MenuBarRingSource,
        ringSense: MenuBarRingSense,
        font: NSFont
    ) -> MenuBarLabel {
        let digits = authState.isAuthenticated
            ? resolveDigits(usageData: usageData, usageDisplay: usageDisplay, showRemainingPercent: showRemainingPercent)
            : MenuBarUsageDigits.Resolved(text: nil, severityUtilization: nil)
        let utilization = digits.severityUtilization
        let percentage = digits.text
        return MenuBarLabel(
            symbolName: "ring.dashed",
            fallbackSymbol: "ring.dashed",
            // The two named windows only. `legacySlotUtilization` below is a digits-only last
            // resort — those slots are arbitrary API buckets, not a window worth gauging.
            variableValue: MenuBarUsageRing.fill(
                source: ringSource,
                sense: ringSense,
                fiveHour: usageData.fiveHourUtilization,
                week: usageData.sevenDayUtilization
            ),
            symbolTint: CodexMenuBarUsageSeverity(usageData.sevenDayUtilization).iconTint,
            text: percentage,
            textTint: percentage == nil ? nil : CodexMenuBarUsageSeverity(utilization).tint,
            font: font,
            accessibilityLabel: String(localized: "PlanMonitor for Codex"),
            accessibilityValue: percentage ?? String(localized: "Not signed in")
        )
    }

    private static func resolveDigits(
        usageData: CodexUsageData,
        usageDisplay: MenuBarUsageDisplay,
        showRemainingPercent: Bool
    ) -> MenuBarUsageDigits.Resolved {
        let primary = MenuBarUsageDigits.resolve(
            display: usageDisplay,
            fiveHour: usageData.fiveHourUtilization,
            week: usageData.sevenDayUtilization,
            showRemainingPercent: showRemainingPercent
        )
        guard primary.text == nil else { return primary }
        // Neither named window is reported, so fall back to the trailing slots rather than blank the
        // label. Kept out of the call above on purpose: these are arbitrary API-named buckets, and
        // in `both` mode one would otherwise be printed as if it were the 5-hour window.
        return MenuBarUsageDigits.resolve(
            display: .fiveHour,
            fiveHour: legacySlotUtilization(usageData),
            week: nil,
            showRemainingPercent: showRemainingPercent
        )
    }

    /// Slots three to five, in order. Named after the Claude donor model — slot three
    /// (`sevenDayOpusUtilization`) is a model-scoped *five-hour* bucket, not a weekly one.
    private static func legacySlotUtilization(_ usageData: CodexUsageData) -> Double? {
        usageData.sevenDayOpusUtilization
            ?? usageData.sevenDaySonnetUtilization
            ?? usageData.extraUsageUtilization
    }
}

enum CodexMenuBarUsageSeverity: Equatable {
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

    /// For the digits: no colour at normal.
    var tint: NSColor? {
        switch self {
        case .normal: nil
        case .warning: Self.warningColor
        case .critical: .systemRed
        }
    }

    /// For the menu-bar glyph: always coloured, matching the weekly usage bar.
    var iconTint: NSColor {
        switch self {
        case .normal: .systemGreen
        case .warning: Self.warningColor
        case .critical: .systemRed
        }
    }

    static let warningColor = NSColor(srgbRed: 0.82, green: 0.42, blue: 0.04, alpha: 1)
}
