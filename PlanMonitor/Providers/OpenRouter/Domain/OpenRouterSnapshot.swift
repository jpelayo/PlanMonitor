import Foundation

/// Everything the UI renders, assembled from the API by `OpenRouterBudgetAssembler`.
/// Contains no key hashes, user ids, or tokens — it is persisted to UserDefaults.
nonisolated struct OpenRouterSnapshot: Codable, Equatable, Sendable {
    var accountCredit: AccountCredit?
    var keyBudgets: [KeyBudget]
    var uncappedKeys: [KeySpend]
    var guardrailBudgets: [GuardrailBudget]
    var guardrailsAvailable: Bool
    /// Spend in the current UTC calendar month. Summed from the live per-key counters,
    /// so it includes today — cross-checked against /activity to within $0.02.
    var spentThisMonth: Decimal?
    /// Rolling 30-day spend: /activity (which ends yesterday) plus today's per-key
    /// total. nil when /activity was unavailable.
    var spentLast30Days: Decimal?
    /// Spend in the trailing 15 minutes, from minute-granularity analytics.
    var spentLast15Minutes: Decimal?
    /// Spend in the trailing hour, same source.
    var spentLastHour: Decimal?
    /// Spend in the current UTC calendar day — the same day boundary the OpenRouter
    /// dashboard uses, so the two agree.
    var spentToday: Decimal?
    /// Rolling 24 hours, which straddles the UTC midnight that `spentToday` resets on.
    var spentLast24Hours: Decimal?
    /// Spend in the current UTC week (Monday start).
    var spentThisWeek: Decimal?
    /// Estimated total for the current calendar month. See `SpendProjection`.
    var projectedThisMonth: Decimal?
    /// Models called in the last 15 minutes, most recently used first.
    var recentModels: [ModelUsage]
    var fetchedAt: Date

    static let empty = OpenRouterSnapshot(
        accountCredit: nil,
        keyBudgets: [],
        uncappedKeys: [],
        guardrailBudgets: [],
        guardrailsAvailable: true,
        spentThisMonth: nil,
        spentLast30Days: nil,
        spentLast15Minutes: nil,
        spentLastHour: nil,
        spentToday: nil,
        spentLast24Hours: nil,
        spentThisWeek: nil,
        projectedThisMonth: nil,
        recentModels: [],
        fetchedAt: .distantPast
    )

    var isEmpty: Bool {
        accountCredit == nil && keyBudgets.isEmpty && uncappedKeys.isEmpty && guardrailBudgets.isEmpty
    }

    /// The most-consumed budget across keys and guardrails. Drives the menu-bar text
    /// tint — the tactical "something is about to break" signal, independent of the
    /// account balance which drives the icon.
    var worstBudgetFraction: Double? {
        let fractions = keyBudgets.map(\.usedFraction) + guardrailBudgets.map(\.worstFraction)
        return fractions.max()
    }

    /// Spend against the pool of every capped key's headroom — the *Limits* ring.
    ///
    /// Each key counts once, at the limit that actually binds it: a key under both its own cap and
    /// a guardrail contributes its spend once and the lower of the two limits. Counting both entries
    /// would double the spend and, worse, credit the key with headroom it does not have. Keys with no
    /// cap at all are left out — there is nothing to gauge them against. `nil` when no key is capped.
    var pooledBudgetFraction: Double? {
        var bindingLimit: [String: (spent: Decimal, limit: Decimal)] = [:]
        func consider(keyHash: String, spent: Decimal, limit: Decimal) {
            if let current = bindingLimit[keyHash], current.limit <= limit { return }
            bindingLimit[keyHash] = (spent, limit)
        }
        for key in keyBudgets {
            consider(keyHash: key.keyHash, spent: key.spent, limit: key.limit)
        }
        for guardrail in guardrailBudgets {
            for member in guardrail.members {
                consider(keyHash: member.keyHash, spent: member.spent, limit: member.limit)
            }
        }
        guard !bindingLimit.isEmpty else { return nil }
        let spent = bindingLimit.values.reduce(Decimal(0)) { $0 + $1.spent }
        let limit = bindingLimit.values.reduce(Decimal(0)) { $0 + $1.limit }
        return Money.fraction(spent: spent, limit: limit)
    }
}

nonisolated struct AccountCredit: Codable, Equatable, Sendable {
    var totalPurchased: Decimal
    var totalUsed: Decimal

    /// Derived — OpenRouter exposes no remaining field. Can be negative; the account
    /// is then blocked from inference and the UI must show the deficit, not zero.
    var remaining: Decimal { totalPurchased - totalUsed }

    var isNegative: Bool { remaining < 0 }

    /// Share of lifetime purchases already spent.
    ///
    /// **Not a health signal.** `totalPurchased` is everything ever bought, not a cap,
    /// so this ratio says nothing about risk: an account topped up $10 at a time sits
    /// near 100% forever while being perfectly fine. Shown as context, never used to
    /// colour anything. The only meaningful credit threshold is the floor at zero.
    var usedFraction: Double? {
        Money.fraction(spent: totalUsed, limit: totalPurchased)
    }

    /// Fraction of lifetime purchases still unspent, clamped to 0...1.
    var remainingFraction: Double? {
        guard let used = usedFraction else { return nil }
        return min(max(1 - used, 0), 1)
    }

    /// Credit has no ceiling, only a floor. Being overdrawn blocks inference; anything
    /// above zero is simply "you have credit".
    var severity: BudgetSeverity {
        remaining <= 0 ? .critical : .normal
    }
}

/// A key with its own spending cap.
nonisolated struct KeyBudget: Codable, Identifiable, Equatable, Sendable {
    var id: String { keyHash }
    var keyHash: String
    var name: String
    var label: String
    var disabled: Bool
    var limit: Decimal
    var remaining: Decimal
    var spent: Decimal
    var window: ResetWindow
    var includesBYOK: Bool
    var usedFraction: Double
    /// True when `limit_remaining` was absent and spend was recomputed from `usage_*`.
    var isApproximate: Bool
}

/// A key with no cap — spend is shown, but there is nothing to gauge against.
nonisolated struct KeySpend: Codable, Identifiable, Equatable, Sendable {
    var id: String { keyHash }
    var keyHash: String
    var name: String
    var label: String
    var disabled: Bool
    var spentInWindow: Decimal
}

/// A guardrail budget. OpenRouter enforces these **per key**, not as a shared pot, so
/// this holds one member per assigned key and its headline is the worst member — never
/// the sum. See build plan §6.2.
nonisolated struct GuardrailBudget: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var limit: Decimal
    var window: ResetWindow
    var includesBYOK: Bool
    var members: [GuardrailKeyBudget]
    var worstFraction: Double

    var hasMembers: Bool { !members.isEmpty }
}

nonisolated struct GuardrailKeyBudget: Codable, Identifiable, Equatable, Sendable {
    var id: String { "\(guardrailID)/\(keyHash)" }
    var guardrailID: String
    var keyHash: String
    var keyName: String
    var keyLabel: String
    var spent: Decimal
    var limit: Decimal
    var usedFraction: Double
    var remaining: Decimal { limit - spent }
    /// True when this key also has a lower personal cap, so the guardrail is not the
    /// binding constraint. The docs say the lower limit wins.
    var supersededByKeyLimit: Bool
}


/// One model's activity inside the recent window.
nonisolated struct ModelUsage: Codable, Identifiable, Equatable, Sendable {
    var id: String { model }
    var model: String
    var spend: Decimal
    var tokens: Int
    var requests: Int
    /// Latest minute bucket the model appeared in — drives "most recently called".
    var lastCalledAt: Date

    /// `vendor/model-name-20260826` is too long for a 360pt popover. Show the model
    /// without its vendor prefix, which is what distinguishes the rows.
    var displayName: String {
        model.split(separator: "/").last.map(String.init) ?? model
    }

    var vendor: String? {
        let parts = model.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : nil
    }
}


