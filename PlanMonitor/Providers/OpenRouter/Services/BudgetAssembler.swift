import Foundation

/// Turns raw API payloads into the snapshot the UI renders.
///
/// Deliberately a pure function: no I/O, no actor, no clock beyond an injected `now`.
/// Every rule that could produce a subtly-wrong number lives here so it can be tested
/// without a network or a mock. See build plan §2 and §6.3.
nonisolated enum OpenRouterBudgetAssembler {

    static func assemble(
        credits: CreditsDTO?,
        keys: [APIKeyDTO],
        guardrails: [GuardrailDTO],
        assignments: [GuardrailKeyAssignmentDTO],
        activity: [ActivityRowDTO]?,
        analytics: [AnalyticsRowDTO]?,
        dayAnalytics: [AnalyticsRowDTO]? = nil,
        recentModelsWindow: RecentModelsWindow = .fifteenMinutes,
        guardrailsAvailable: Bool,
        now: Date
    ) -> OpenRouterSnapshot {
        let account = credits.map {
            AccountCredit(totalPurchased: $0.totalCredits, totalUsed: $0.totalUsage)
        }

        var keyBudgets: [KeyBudget] = []
        var uncapped: [KeySpend] = []
        for key in keys {
            if let budget = makeKeyBudget(key, now: now) {
                keyBudgets.append(budget)
            } else {
                uncapped.append(
                    KeySpend(
                        keyHash: key.hash,
                        name: key.displayName,
                        label: key.label ?? "",
                        disabled: key.disabled ?? false,
                        spentInWindow: key.usage(in: nil)
                    )
                )
            }
        }

        let guardrailBudgets = makeGuardrailBudgets(
            guardrails: guardrails,
            assignments: assignments,
            keys: keys,
            keyBudgets: keyBudgets,
            now: now
        )

        // Worst first: the thing about to break belongs at the top of the list.
        keyBudgets.sort { $0.usedFraction > $1.usedFraction }
        uncapped.sort { $0.spentInWindow > $1.spentInWindow }

        // Current-month spend needs no extra request: the per-key monthly counters are
        // already live and already include today.
        let spentThisMonth = keys.isEmpty ? nil : keys.reduce(Decimal(0)) { $0 + $1.usage(in: .monthly) }
        let spentToday = keys.reduce(Decimal(0)) { $0 + $1.usage(in: .daily) }
        let spentLast30Days = activity.map { rows in
            rows.reduce(Decimal(0)) { $0 + ($1.usage ?? 0) } + spentToday
        }

        let recent = analytics.map { rows in RecentActivity(rows: rows, now: now) }

        // Short windows reuse the minute feed; long ones need the hourly feed, which
        // is the only one that reaches back a full day.
        let modelSource = recentModelsWindow.usesMinuteGranularity ? analytics : dayAnalytics
        let recentModels = modelSource.map {
            RecentActivity.models(from: $0, window: recentModelsWindow, now: now)
        } ?? []

        let spentThisWeek = keys.isEmpty ? nil : keys.reduce(Decimal(0)) { $0 + $1.usage(in: .weekly) }
        // Rolling 24 hours, from the hourly query. Distinct from `spentToday`, which
        // resets at UTC midnight.
        let spentLast24Hours = dayAnalytics.map { rows in
            rows.reduce(Decimal(0)) { $0 + ($1.totalUsage?.value ?? 0) }
        }
        let projected = SpendProjection.project(
            spentThisMonth: spentThisMonth,
            spentThisWeek: spentThisWeek,
            spentLast24Hours: spentLast24Hours,
            now: now
        )

        return OpenRouterSnapshot(
            accountCredit: account,
            keyBudgets: keyBudgets,
            uncappedKeys: uncapped,
            guardrailBudgets: guardrailBudgets,
            guardrailsAvailable: guardrailsAvailable,
            spentThisMonth: spentThisMonth,
            spentLast30Days: spentLast30Days,
            spentLast15Minutes: recent?.spentLast15Minutes,
            spentLastHour: recent?.spentLastHour,
            spentToday: keys.isEmpty ? nil : spentToday,
            spentLast24Hours: spentLast24Hours,
            spentThisWeek: spentThisWeek,
            projectedThisMonth: projected,
            recentModels: recentModels,
            fetchedAt: now
        )
    }

    // MARK: - Key budgets

    private static func makeKeyBudget(_ key: APIKeyDTO, now: Date) -> KeyBudget? {
        // No cap means nothing to gauge against — the key is listed as spend only.
        guard let limit = key.limit, limit > 0 else { return nil }

        let interval = key.resetInterval
        let includesBYOK = key.includeBYOKInLimit ?? false

        // `limit_remaining` is server-side truth and already applies the BYOK rule.
        // Recompute only when it is absent, and flag those rows as approximate.
        let spent: Decimal
        let remaining: Decimal
        let approximate: Bool
        if let limitRemaining = key.limitRemaining {
            remaining = limitRemaining
            spent = limit - limitRemaining
            approximate = false
        } else {
            var computed = key.usage(in: interval)
            if includesBYOK { computed += key.byokUsage(in: interval) }
            spent = computed
            remaining = limit - computed
            approximate = true
        }

        return KeyBudget(
            keyHash: key.hash,
            name: key.displayName,
            label: key.label ?? "",
            disabled: key.disabled ?? false,
            limit: limit,
            remaining: remaining,
            spent: spent,
            window: ResetWindowCalculator.window(for: interval, now: now),
            includesBYOK: includesBYOK,
            usedFraction: Money.fraction(spent: spent, limit: limit) ?? 0,
            isApproximate: approximate
        )
    }

    // MARK: - Guardrail budgets

    private static func makeGuardrailBudgets(
        guardrails: [GuardrailDTO],
        assignments: [GuardrailKeyAssignmentDTO],
        keys: [APIKeyDTO],
        keyBudgets: [KeyBudget],
        now: Date
    ) -> [GuardrailBudget] {
        let keysByHash = Dictionary(keys.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
        let keyLimitFractions = Dictionary(
            keyBudgets.map { ($0.keyHash, $0.usedFraction) },
            uniquingKeysWith: { first, _ in first }
        )

        var membersByGuardrail: [String: [GuardrailKeyBudget]] = [:]
        for assignment in assignments {
            // An assignment can outlive its key or guardrail (deletion, or a key beyond
            // a page boundary). Skip it — never crash, never invent a zero.
            guard let guardrail = guardrails.first(where: { $0.id == assignment.guardrailID }),
                  let key = keysByHash[assignment.keyHash] else { continue }

            // Policy-only guardrails (models, providers, ZDR, filters) carry no budget.
            guard let limit = guardrail.limitUSD, limit > 0 else { continue }

            let interval = guardrail.interval
            // The window must match the guardrail's own interval. Measuring a monthly
            // guardrail against usage_daily would under-report it all month.
            var spent = key.usage(in: interval)
            if guardrail.includeBYOKInBudgets ?? false {
                spent += key.byokUsage(in: interval)
            }

            let fraction = Money.fraction(spent: spent, limit: limit) ?? 0
            let member = GuardrailKeyBudget(
                guardrailID: guardrail.id,
                keyHash: key.hash,
                keyName: assignment.keyName ?? key.displayName,
                keyLabel: assignment.keyLabel ?? key.label ?? "",
                spent: spent,
                limit: limit,
                usedFraction: fraction,
                // When the key's own cap is further along, that cap binds first.
                supersededByKeyLimit: (keyLimitFractions[key.hash] ?? 0) > fraction
            )
            membersByGuardrail[guardrail.id, default: []].append(member)
        }

        var budgets: [GuardrailBudget] = []
        for guardrail in guardrails {
            guard let limit = guardrail.limitUSD, limit > 0 else { continue }
            var members = membersByGuardrail[guardrail.id] ?? []
            members.sort { $0.usedFraction > $1.usedFraction }

            budgets.append(
                GuardrailBudget(
                    id: guardrail.id,
                    name: guardrail.displayName,
                    limit: limit,
                    window: ResetWindowCalculator.window(for: guardrail.interval, now: now),
                    includesBYOK: guardrail.includeBYOKInBudgets ?? false,
                    members: members,
                    // MAX, never the sum: each assigned key gets its own independent
                    // budget of `limit`, so four keys at 30% is 30%, not 120%.
                    worstFraction: members.map(\.usedFraction).max() ?? 0
                )
            )
        }

        budgets.sort { $0.worstFraction > $1.worstFraction }
        return budgets
    }
}


/// Folds minute-granularity analytics rows into the trailing-window figures.
///
/// One query covers both: the hour total is every row, the 15-minute total is the
/// subset inside that window. Rows without a parseable bucket are dropped rather than
/// silently counted into the wrong window.
nonisolated private struct RecentActivity {
    var spentLast15Minutes: Decimal = 0
    var spentLastHour: Decimal = 0

    init(rows: [AnalyticsRowDTO], now: Date) {
        let fifteenMinutesAgo = now.addingTimeInterval(-15 * 60)
        for row in rows {
            guard let bucket = row.bucket else { continue }
            let spend = row.totalUsage?.value ?? 0
            spentLastHour += spend
            if bucket >= fifteenMinutesAgo { spentLast15Minutes += spend }
        }
    }

    /// Groups rows by model inside the window, newest call first.
    ///
    /// Buckets are start-of-interval stamps, so an hourly bucket at 14:00 covers calls
    /// up to 14:59. Including a bucket whose *end* falls inside the window keeps the
    /// current partial hour from being dropped.
    static func models(
        from rows: [AnalyticsRowDTO],
        window: RecentModelsWindow,
        now: Date
    ) -> [ModelUsage] {
        let cutoff = now.addingTimeInterval(-Double(window.minutes) * 60)
        let bucketLength: TimeInterval = window.usesMinuteGranularity ? 60 : 3600

        var byModel: [String: ModelUsage] = [:]
        for row in rows {
            guard let bucket = row.bucket,
                  bucket.addingTimeInterval(bucketLength) > cutoff,
                  let model = row.model, !model.isEmpty else { continue }

            let spend = row.totalUsage?.value ?? 0
            if var existing = byModel[model] {
                existing.spend += spend
                existing.tokens += row.tokensTotal?.intValue ?? 0
                existing.requests += row.requestCount?.intValue ?? 0
                existing.lastCalledAt = max(existing.lastCalledAt, bucket)
                byModel[model] = existing
            } else {
                byModel[model] = ModelUsage(
                    model: model,
                    spend: spend,
                    tokens: row.tokensTotal?.intValue ?? 0,
                    requests: row.requestCount?.intValue ?? 0,
                    lastCalledAt: bucket
                )
            }
        }

        return byModel.values
            .sorted { ($0.lastCalledAt, $0.spend) > ($1.lastCalledAt, $1.spend) }
            .prefix(5)
            .map { $0 }
    }
}
