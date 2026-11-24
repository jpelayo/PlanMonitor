import AppKit
import SwiftUI

/// Google AI's menu-bar label:
///   icon → the most-used of all agy's buckets, coloured by severity
///   text → the Gemini models' 5-hour window, tinted by its used share
/// The glyph is `australsign.ring.dashed` (₳, user decision 2026-11-23): an A in the dashed ring,
/// in the family of Claude's `₵`, Grok's `₲`, OpenRouter's `$`, Claude-API's `€` and OpenCode's `₧`
/// — not a statement about currency.
enum GoogleAIMenuBarLabel {
    static let symbolName = "australsign.ring.dashed"

    static func make(
        usage: GoogleAIUsage,
        showsUsage: Bool,
        showRemainingPercent: Bool,
        font: NSFont
    ) -> MenuBarLabel {
        let digits = showsUsage
            ? GoogleAIMenuBarDigits.resolve(usage: usage, showRemainingPercent: showRemainingPercent)
            : GoogleAIMenuBarDigits.Resolved(text: nil, severityFraction: nil)
        let worst = showsUsage ? usage.worstUsedFraction : nil

        return MenuBarLabel(
            symbolName: symbolName,
            fallbackSymbol: "ring.dashed",
            variableValue: nil,
            symbolTint: GoogleAISeverity(worst).iconTint,
            text: digits.text,
            textTint: digits.text == nil ? nil : GoogleAISeverity(digits.severityFraction).tint,
            font: font,
            accessibilityLabel: String(localized: "PlanMonitor for Google AI"),
            accessibilityValue: digits.text ?? String(localized: "Not set up")
        )
    }
}

/// `OpenCodeSeverity`, copied and renamed rather than shared: one module is one namespace.
/// Thresholds on a *used* fraction.
nonisolated enum GoogleAISeverity: Equatable, Sendable {
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

    var tint: NSColor? {
        switch self {
        case .normal: nil
        case .warning: Self.warningColor
        case .critical: .systemRed
        }
    }

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
