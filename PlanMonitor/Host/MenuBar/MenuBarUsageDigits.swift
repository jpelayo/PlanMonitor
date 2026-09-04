import Foundation

/// The digits a provider shows for its percentage windows, and the used-percentage that should tint
/// them.
///
/// Deliberately takes plain numbers: the provider decides which of *its* counters is "the 5-hour
/// window" and which is "the main weekly limit". Nothing here knows about Claude's, Codex's or
/// Grok's usage models, and nothing here picks a colour — each provider maps
/// `severityUtilization` through its own severity enum, which is why those enums stay duplicated.
nonisolated enum MenuBarUsageDigits {
    struct Resolved: Equatable, Sendable {
        var text: String?
        /// The *used* percentage of the worse window on show, whatever the digits display.
        var severityUtilization: Double?
    }

    /// Both inputs are used percentages on a 0–100 scale.
    static func resolve(
        display: MenuBarUsageDisplay,
        fiveHour: Double?,
        week: Double?,
        showRemainingPercent: Bool
    ) -> Resolved {
        // Symmetric degradation: a selection whose window has no value falls back to the other, so
        // the digits are never blank while any data exists.
        let shown: [Double]
        switch display {
        case .fiveHour: shown = [fiveHour ?? week].compactMap { $0 }
        case .week: shown = [week ?? fiveHour].compactMap { $0 }
        case .both: shown = [fiveHour, week].compactMap { $0 }
        }
        guard !shown.isEmpty else { return Resolved(text: nil, severityUtilization: nil) }

        // Truncating, not rounding: every provider truncated before this helper existed, and
        // rounding here would quietly change the digits for every existing user.
        let text = shown
            .map { "\(Int(showRemainingPercent ? max(0, 100 - $0) : $0))%" }
            .joined(separator: "\u{00B7}")
        return Resolved(text: text, severityUtilization: shown.max())
    }
}
