import Foundation

/// What fills the ring around OpenCode's menu-bar glyph. Persisted under `opencode.ringSource`.
/// Every source fills with what is **left** — of a Go window or of the monthly budget — as the
/// other money providers' rings do.
nonisolated enum OpenCodeRingSource: String, CaseIterable, Sendable {
    /// The whole ring, as the other providers' "Disabled".
    case off
    case goRolling
    case goWeekly
    case goMonthly
    /// What is left of the member's monthly budget.
    case budget

    var displayName: String {
        switch self {
        case .off: String(localized: "Disabled")
        case .goRolling: String(localized: "Go 5-hour limit")
        case .goWeekly: String(localized: "Go weekly limit")
        case .goMonthly: String(localized: "Go monthly limit")
        case .budget: String(localized: "Monthly budget")
        }
    }

    /// What 100% means, shown under the picker in Settings.
    var caption: String? {
        switch self {
        case .off: nil
        case .goRolling, .goWeekly, .goMonthly: String(localized: "A full ring is an unused window.")
        case .budget: String(localized: "A full ring is your monthly budget.")
        }
    }

    /// The fill for `MenuBarLabel.variableValue`, quantised to the ring's dashes. `nil` — nothing
    /// to measure against — leaves the ring whole, as `off` does. A Go source falls back to the
    /// nearest reported window, as the digits do.
    func fill(for snapshot: OpenCodeSnapshot) -> Double? {
        let used: Double?
        switch self {
        case .off:
            return nil
        case .goRolling:
            used = snapshot.go?.window(preferring: .rolling).map { $0.effectivePercent / 100 }
        case .goWeekly:
            used = snapshot.go?.window(preferring: .weekly).map { $0.effectivePercent / 100 }
        case .goMonthly:
            used = snapshot.go?.window(preferring: .monthly).map { $0.effectivePercent / 100 }
        case .budget:
            used = snapshot.usedFraction
        }
        return used.map { MenuBarUsageRing.quantise(min(max(1 - $0, 0), 1)) }
    }
}
