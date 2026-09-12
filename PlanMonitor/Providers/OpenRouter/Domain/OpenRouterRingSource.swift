import Foundation

/// What fills the ring around OpenRouter's menu-bar glyph.
///
/// Its own enum rather than `MenuBarRingSource`: OpenRouter tracks money, not a 5-hour or weekly
/// window, so its gauges are different in kind. Persisted under `openrouter.ringSource`.
nonisolated enum OpenRouterRingSource: String, CaseIterable, Sendable {
    /// The whole ring, as the other providers' "Disabled".
    case off
    /// Remaining balance against the balance right after the last top-up — see `CreditRingMark`.
    case credit
    /// Pooled headroom across every capped key, each counted once at the limit that binds it.
    case limits
    /// The single tightest key or guardrail budget — the ring OpenRouter drew before this setting.
    case worst

    var displayName: String {
        switch self {
        case .off: String(localized: "Disabled")
        case .credit: String(localized: "Credit")
        case .limits: String(localized: "Limits")
        case .worst: String(localized: "Worst budget")
        }
    }
}
