import Foundation

/// The 100% of OpenRouter's *Credit* ring: the balance seen right after the most recent top-up.
///
/// Lifetime credit has no ceiling worth gauging against — `totalPurchased` only ever grows — but the
/// balance at the moment you last loaded credit is a real denominator, and it resets exactly when the
/// account does. So the mark is re-seeded on every increase in remaining credit, however small: load
/// $1 onto $10 and the ring is full again at $11. The comparison is against the *previous
/// observation*, not the mark, or draining 50 → 10 and loading 1 would leave the mark at 50.
///
/// Pure and value-typed so the rule is testable without the view model. Persisted as two exact
/// decimal strings; a mark forgotten at every launch would read 100% at every startup.
nonisolated struct CreditRingMark: Equatable, Sendable {
    /// The balance that reads as a full ring. `nil` until credit has been observed once.
    var mark: Decimal?
    /// The balance at the previous observation, so the next one can tell a top-up from spend.
    var lastRemaining: Decimal?

    init(mark: Decimal? = nil, lastRemaining: Decimal? = nil) {
        self.mark = mark
        self.lastRemaining = lastRemaining
    }

    /// The state after seeing `credit`: seeds the mark on first sight, re-seeds it on any increase.
    func observing(_ credit: AccountCredit) -> CreditRingMark {
        let remaining = credit.remaining
        var next = self
        if let last = lastRemaining, mark != nil {
            if remaining > last { next.mark = remaining }
        } else {
            next.mark = remaining
        }
        next.lastRemaining = remaining
        return next
    }

    /// How full the ring sits for `credit`, on the ring's twelve steps. Overdrawn pins it empty,
    /// because that state is real; no usable mark leaves the ring whole.
    func fill(for credit: AccountCredit) -> Double? {
        if credit.isNegative { return 0 }
        guard let mark, mark > 0 else { return nil }
        let fraction = NSDecimalNumber(decimal: credit.remaining).doubleValue
            / NSDecimalNumber(decimal: mark).doubleValue
        return MenuBarUsageRing.quantise(min(max(fraction, 0), 1))
    }

    // MARK: - Persistence

    private static let markKey = "openrouter.creditRingMark"
    private static let lastRemainingKey = "openrouter.creditRingLastRemaining"

    static func load(from defaults: UserDefaults) -> CreditRingMark {
        CreditRingMark(
            mark: defaults.string(forKey: markKey).flatMap { Decimal(string: $0) },
            lastRemaining: defaults.string(forKey: lastRemainingKey).flatMap { Decimal(string: $0) }
        )
    }

    /// Exact decimal strings, never a `Double` round trip. Clears both keys when there is no mark.
    func save(to defaults: UserDefaults) {
        guard let mark else {
            defaults.removeObject(forKey: Self.markKey)
            defaults.removeObject(forKey: Self.lastRemainingKey)
            return
        }
        defaults.set("\(mark)", forKey: Self.markKey)
        if let lastRemaining {
            defaults.set("\(lastRemaining)", forKey: Self.lastRemainingKey)
        } else {
            defaults.removeObject(forKey: Self.lastRemainingKey)
        }
    }
}
