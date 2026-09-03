//
//  ClaudeMenuBarIconLabel.swift
//  PlanTracker
//

import AppKit

/// Claude's menu-bar label: the icon follows weekly severity, the digits follow the 5-hour
/// window. Rendered by `StatusItemController` as a real AppKit title, never rasterised.
enum ClaudeMenuBarLabel {
    static func make(
        usageData: ClaudeUsageData,
        authState: ClaudeAuthState,
        showRemainingPercent: Bool,
        font: NSFont
    ) -> MenuBarLabel {
        let percentage = displayPercentage(usageData: usageData, authState: authState, showRemainingPercent: showRemainingPercent)
        return MenuBarLabel(
            symbolName: "cedisign.ring.dashed",
            fallbackSymbol: "ring.dashed",
            symbolTint: ClaudeMenuBarUsageSeverity(usageData.sevenDayUtilization).iconTint,
            text: percentage,
            textTint: percentage == nil ? nil : ClaudeMenuBarUsageSeverity(usageData.fiveHourUtilization).tint,
            font: font,
            accessibilityLabel: String(localized: "PlanMonitor for Claude"),
            accessibilityValue: percentage ?? String(localized: "Not signed in")
        )
    }

    private static func displayPercentage(
        usageData: ClaudeUsageData,
        authState: ClaudeAuthState,
        showRemainingPercent: Bool
    ) -> String? {
        guard authState.isAuthenticated else { return nil }

        if showRemainingPercent {
            guard let remaining = usageData.fiveHourRemaining else { return nil }
            return "\(Int(remaining))%"
        } else {
            guard let utilization = usageData.fiveHourUtilization else { return nil }
            return "\(Int(utilization))%"
        }
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
