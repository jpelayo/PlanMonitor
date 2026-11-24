import Foundation

/// The text the Google AI menu-bar item shows, and the used fraction that should tint it: the
/// Gemini models' 5-hour window (user decision 2026-11-23), in the global remaining/used sense.
/// Truncated and written `45%`, as the other providers write theirs. No such window draws
/// nothing — never `0%`.
nonisolated enum GoogleAIMenuBarDigits {
    struct Resolved: Equatable, Sendable {
        var text: String?
        /// The *used* share on show, whatever sense the digits read in. `nil` when nothing is shown.
        var severityFraction: Double?
    }

    static func resolve(usage: GoogleAIUsage, showRemainingPercent: Bool) -> Resolved {
        guard let bucket = usage.geminiFiveHour else { return Resolved(text: nil, severityFraction: nil) }
        let usedPercent = bucket.used * 100
        let shown = showRemainingPercent ? max(0, 100 - usedPercent) : usedPercent
        return Resolved(text: "\(Int(shown + 1e-9))%", severityFraction: bucket.used)
    }
}
