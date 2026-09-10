import AppKit

/// Grok's menu-bar label: one weekly pool drives icon, ring and digits alike. Grok reports no
/// hourly window, so every `MenuBarUsageDisplay` and `MenuBarRingSource` option resolves to that
/// weekly pool.
enum GrokMenuBarLabel {
    static func make(
        usageData: GrokUsageData,
        authState: GrokAuthState,
        showRemainingPercent: Bool,
        usageDisplay: MenuBarUsageDisplay,
        ringSource: MenuBarRingSource,
        ringSense: MenuBarRingSense,
        font: NSFont
    ) -> MenuBarLabel {
        let severity = GrokMenuBarUsageSeverity(usageData.usedPercent)
        let percentage = authState.showsUsage
            ? MenuBarUsageDigits.resolve(
                display: usageDisplay,
                fiveHour: nil,
                week: usageData.usedPercent,
                showRemainingPercent: showRemainingPercent
            ).text
            : nil
        return MenuBarLabel(
            symbolName: "guaranisign.ring.dashed",
            fallbackSymbol: "ring.dashed",
            variableValue: MenuBarUsageRing.fill(
                source: ringSource,
                sense: ringSense,
                fiveHour: nil,
                week: usageData.usedPercent
            ),
            symbolTint: severity.iconTint,
            text: percentage,
            textTint: percentage == nil ? nil : severity.tint,
            font: font,
            accessibilityLabel: String(localized: "Grok usage"),
            accessibilityValue: percentage ?? String(localized: "Not connected")
        )
    }
}

private enum GrokMenuBarUsageSeverity {
    case normal
    case warning
    case critical

    init(_ used: Double?) {
        switch used {
        case nil, .some(..<65): self = .normal
        case .some(65..<90): self = .warning
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
