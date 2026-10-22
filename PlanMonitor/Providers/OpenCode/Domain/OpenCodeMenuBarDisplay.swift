import Foundation

/// What the OpenCode menu-bar item shows: one Go window's percentage, in the sense the global
/// "Show percentage" picks, as Claude, Codex and Grok do (user decision, 2026-10-22).
///
/// Pending: a **balance** choice, and the item switching to the balance when the chosen Go window
/// fills, as long as there is some (user decision, 2026-10-22). No endpoint a key can read reports
/// the balance — `console/api/billing/status` answers 403 to every key, and only a signed-in console
/// session reads it (OpenCode issue #10448) — so both wait for that.
nonisolated enum OpenCodeMenuBarDisplay: String, CaseIterable, Sendable {
    case goRolling
    case goWeekly
    case goMonthly

    /// The 5-hour window, the one Go rate-limits on first.
    static let `default` = OpenCodeMenuBarDisplay.goRolling

    var displayName: String {
        switch self {
        case .goRolling: String(localized: "Go 5-hour limit")
        case .goWeekly: String(localized: "Go weekly limit")
        case .goMonthly: String(localized: "Go monthly limit")
        }
    }

    var goKind: OpenCodeGoUsage.Kind {
        switch self {
        case .goRolling: .rolling
        case .goWeekly: .weekly
        case .goMonthly: .monthly
        }
    }
}
