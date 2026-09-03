//
//  CodexMenuBarIconLabel.swift
//  PlanTracker
//

import AppKit

/// Codex's menu-bar label: weekly severity drives the icon, the displayed compact window
/// (5-hour, falling back to weekly and the other slots) drives the digits.
enum CodexMenuBarLabel {
    static func make(
        usageData: CodexUsageData,
        authState: CodexAuthState,
        showRemainingPercent: Bool,
        font: NSFont
    ) -> MenuBarLabel {
        let utilization = displayUtilization(usageData)
        let percentage = displayPercentage(usageData: usageData, authState: authState, showRemainingPercent: showRemainingPercent)
        return MenuBarLabel(
            symbolName: "ring.dashed",
            fallbackSymbol: "ring.dashed",
            symbolTint: CodexMenuBarUsageSeverity(usageData.sevenDayUtilization).iconTint,
            text: percentage,
            textTint: percentage == nil ? nil : CodexMenuBarUsageSeverity(utilization).tint,
            font: font,
            accessibilityLabel: String(localized: "PlanMonitor for Codex"),
            accessibilityValue: percentage ?? String(localized: "Not signed in")
        )
    }

    private static func displayPercentage(
        usageData: CodexUsageData,
        authState: CodexAuthState,
        showRemainingPercent: Bool
    ) -> String? {
        guard authState.isAuthenticated else { return nil }
        guard let utilization = displayUtilization(usageData) else { return nil }

        if showRemainingPercent {
            return "\(Int(100 - utilization))%"
        } else {
            return "\(Int(utilization))%"
        }
    }

    /// Compact fallback order: five-hour, weekly, model slots, then extra usage.
    private static func displayUtilization(_ usageData: CodexUsageData) -> Double? {
        usageData.fiveHourUtilization
            ?? usageData.sevenDayUtilization
            ?? usageData.sevenDayOpusUtilization
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
