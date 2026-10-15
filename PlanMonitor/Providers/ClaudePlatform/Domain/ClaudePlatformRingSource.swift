import Foundation

/// What fills the ring around Claude-API's menu-bar glyph.
///
/// Its own enum rather than `MenuBarRingSource`, as `OpenRouterRingSource` is: this provider
/// tracks money, not a five-hour or weekly window. Persisted under `claudeapi.ringSource`. Both
/// gauges fill with what is **left**, as OpenRouter's rings do.
nonisolated enum ClaudePlatformRingSource: String, CaseIterable, Sendable {
    /// The whole ring, as the other providers' "Disabled".
    case off
    /// Promotional credit remaining against the credit as granted.
    case promo
    /// Headroom under the account's own spend limit, else Anthropic's (`spendCeiling`).
    case spend

    var displayName: String {
        switch self {
        case .off: String(localized: "Disabled")
        case .promo: String(localized: "Promotional credit")
        case .spend: String(localized: "Spend limit")
        }
    }

    /// What 100% means, shown under the picker in Settings.
    var caption: String? {
        switch self {
        case .off: nil
        case .promo: String(localized: "A full ring is the promotional credit as granted.")
        case .spend: String(localized: "A full ring is your own spend limit, or Anthropic's when you have not set one.")
        }
    }

    /// The fill for `MenuBarLabel.variableValue`, quantised to the ring's dashes. `nil` leaves the
    /// ring whole, which is also what a gauge with no denominator draws.
    func fill(for snapshot: ClaudePlatformSnapshot) -> Double? {
        let remainingFraction: Double?
        switch self {
        case .off:
            return nil
        case .promo:
            guard let granted = snapshot.promoGranted, granted > 0,
                  let remaining = snapshot.promoRemaining else { return nil }
            remainingFraction = Double(remaining) / Double(granted)
        case .spend:
            remainingFraction = snapshot.spendUsedFraction.map { 1 - $0 }
        }
        return remainingFraction.map { MenuBarUsageRing.quantise(min(max($0, 0), 1)) }
    }
}
