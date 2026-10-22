import Foundation

/// The text the OpenCode menu-bar item shows, and the used fraction that should tint it.
///
/// Plain numbers in, text out, no colour decided here. Percentages are truncated and written
/// `61%`, as `MenuBarUsageDigits` writes them for Claude, Codex and Grok.
nonisolated enum OpenCodeMenuBarDigits {
    struct Resolved: Equatable, Sendable {
        var text: String?
        /// The *used* share of the window on show, whatever sense the digits read in, so tint
        /// means one thing everywhere. `nil` when nothing is on show.
        var severityFraction: Double?
    }

    /// The window asked for, else the nearest one reported, so a choice never blanks while any Go
    /// window exists. No Go subscription draws nothing — never `0%`.
    static func resolve(
        display: OpenCodeMenuBarDisplay,
        go: OpenCodeGoUsage?,
        showRemainingPercent: Bool
    ) -> Resolved {
        guard let window = go?.window(preferring: display.goKind) else { return .nothing }
        let percent = window.effectivePercent
        return Resolved(
            text: "\(Int(showRemainingPercent ? max(0, 100 - percent) : percent))%",
            severityFraction: percent / 100
        )
    }
}

private extension OpenCodeMenuBarDigits.Resolved {
    // `nonisolated`: an extension's members default to the main actor in this target, and the
    // resolver that reads this is not on it.
    nonisolated static let nothing = Self(text: nil, severityFraction: nil)
}
