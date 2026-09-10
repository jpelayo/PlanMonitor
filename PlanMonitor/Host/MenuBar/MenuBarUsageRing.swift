import Foundation

/// How full the ring around a provider's menu-bar glyph is drawn.
///
/// Companion to `MenuBarUsageDigits`, and deliberately the same shape: it takes plain used
/// percentages, knows nothing about any provider's usage model, and picks no colour. The ring is
/// the SF Symbol's own variable-value fill, so this returns exactly what `MenuBarLabel.variableValue`
/// wants — `nil` meaning "leave the ring whole".
nonisolated enum MenuBarUsageRing {
    /// `ring.dashed` is twelve dashes and has no finer resolution: measured, the rendered image
    /// changes only at each twelfth. Quantising to that here is what keeps `MenuBarLabel` equality
    /// from re-rendering the status item for a change nobody can see.
    static let steps = 12

    /// Both inputs are used percentages on a 0–100 scale, matching `MenuBarUsageDigits.resolve`.
    static func fill(
        source: MenuBarRingSource,
        sense: MenuBarRingSense,
        fiveHour: Double?,
        week: Double?
    ) -> Double? {
        // Symmetric degradation, as the digits do: the chosen window falling back to the other
        // beats a ring that silently reverts to full. Grok has no hourly window at all, so its
        // `fiveHour` option always lands here.
        let used: Double?
        switch source {
        case .off: return nil
        case .fiveHour: used = fiveHour ?? week
        case .week: used = week ?? fiveHour
        }
        guard let used else { return nil }

        let consumed = min(max(used / 100, 0), 1)
        let shown = sense == .remaining ? 1 - consumed : consumed
        return (shown * Double(steps)).rounded() / Double(steps)
    }
}
