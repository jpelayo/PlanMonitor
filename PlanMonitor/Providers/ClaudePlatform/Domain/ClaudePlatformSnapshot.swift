import Foundation

/// Everything the Claude-API dropdown and menu-bar label draw, from one poll of the console.
///
/// All money is integer **minor units** in `currency`, scaled by `exponent` (§1.2 of the plan:
/// the console's `_usd` fields are cents despite their names). Every figure is optional because the
/// console returns `null` for what does not apply to an account — a pre-paid org has nothing to
/// invoice, a post-paid one no credit — and **`nil` means "not reported", never zero**.
nonisolated struct ClaudePlatformSnapshot: Codable, Equatable, Sendable {
    /// The ISO code `prepaid/credits` reports, or `nil` when it reports none — never assumed.
    var currency: String?
    var exponent: Int

    /// Promotional credit, summed across `promo_tranches`.
    var promoGranted: Int?
    var promoRemaining: Int?
    /// The earliest tranche expiry — the grant's own clock, unrelated to the spend month.
    var promoExpiresAt: Date?
    /// The first tranche's own name, e.g. "API credit (Max 20x)".
    var promoName: String?

    /// Card-paid, non-promotional credit: `amount_without_scoped_credits`.
    var prepaidRemaining: Int?
    /// Post-paid usage accrued and not yet invoiced: `pending_invoice_amount_cents`.
    var pendingInvoice: Int?

    /// `current_spend.amount`, and the calendar-month reset it counts towards.
    var spendUsed: Int?
    var spendResetsAt: Date?
    /// `enforced_limit_usd`: Anthropic's cap for the org, the ceiling of last resort. The account's
    /// own limit sits below it and is what the gauge measures against (`spendCeiling`).
    var enforcedSpendLimit: Int?
    /// The account's own limits, lowest first.
    var selfSelectedLimits: [SpendLimit]

    /// `prepaid/auto_recharge`. `nil` when that endpoint did not answer.
    var autoRecharge: AutoRecharge?

    /// The buckets named different currencies. The figures stay, but pairing them on the menu bar
    /// would mislabel one, so the view model reports it as degraded.
    var currencyMismatch: Bool

    nonisolated struct SpendLimit: Codable, Equatable, Sendable {
        nonisolated enum Action: String, Codable, Sendable {
            case notifyOnly = "notify_only"
            case notifyAndPause = "notify_and_pause"
            case unknown
        }

        var amount: Int
        var action: Action
    }

    nonisolated struct AutoRecharge: Codable, Equatable, Sendable {
        var isEnabled: Bool
        /// Top the balance back up to this…
        var targetAmount: Int?
        /// …whenever it falls below this.
        var thresholdAmount: Int?
    }

    static let empty = ClaudePlatformSnapshot(
        currency: nil,
        exponent: ClaudePlatformMoney.defaultExponent,
        promoGranted: nil,
        promoRemaining: nil,
        promoExpiresAt: nil,
        promoName: nil,
        prepaidRemaining: nil,
        pendingInvoice: nil,
        spendUsed: nil,
        spendResetsAt: nil,
        enforcedSpendLimit: nil,
        selfSelectedLimits: [],
        autoRecharge: nil,
        currencyMismatch: false
    )

    var isEmpty: Bool { self == .empty }

    // MARK: - Derived

    /// What the menu-bar resolver needs, already in its own terms.
    var figures: ClaudePlatformMenuBarDigits.Figures {
        ClaudePlatformMenuBarDigits.Figures(
            available: totalAvailable,
            consumed: spendUsed,
            userLimit: pauseLimit,
            currency: currency,
            exponent: exponent
        )
    }

    /// The menu bar's one sum of what is available: every promotional credit granted plus the
    /// paid credit on the books (user decision, 2026-10-14). The console reports paid credit as its
    /// current balance, not as the total ever bought, so that is the figure counted. Consumption is
    /// the other sum, `spendUsed`, which resets monthly so available minus consumed returns to the
    /// full amount — while the dropdown's promotional row keeps the grant's own balance and expiry.
    var totalAvailable: Int? {
        guard promoGranted != nil || prepaidRemaining != nil else { return nil }
        return (promoGranted ?? 0) + (prepaidRemaining ?? 0)
    }

    /// Promotional credit consumed, as a fraction of the grant. Gauges show used, never remaining.
    var promoUsedFraction: Double? {
        guard let granted = promoGranted, granted > 0, let remaining = promoRemaining else { return nil }
        let remainingForGauge = remaining < ClaudePlatformMoney.gaugeDustThresholdMinorUnits ? 0 : remaining
        return Double(granted - remainingForGauge) / Double(granted)
    }

    /// The limit spend is measured against: the account's own limit — the `self_selected_spend_limit`
    /// marked `notify_and_pause` — when it set one, else Anthropic's cap; the lower of the two if
    /// both. A `notify_only` limit is a reminder, not a ceiling.
    var spendCeiling: Int? {
        [pauseLimit, enforcedSpendLimit].compactMap { $0 }.min()
    }

    /// Spend against `spendCeiling`. May exceed 1 — overspend is real.
    var spendUsedFraction: Double? {
        ClaudePlatformMoney.usedFraction(used: spendUsed, limit: spendCeiling)
    }

    /// The limit that pauses requests, when the account set one.
    var pauseLimit: Int? {
        selfSelectedLimits.first { $0.action == .notifyAndPause }?.amount
    }

    /// The limit that only notifies, when the account set one.
    var notifyLimit: Int? {
        selfSelectedLimits.first { $0.action == .notifyOnly }?.amount
    }

    func format(_ minorUnits: Int, style: CurrencyStyle) -> String {
        ClaudePlatformMoney.format(minorUnits: minorUnits, currency: currency, exponent: exponent, style: style)
    }
}
