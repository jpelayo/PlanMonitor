import Foundation

/// Deterministic fixture for screenshots, UI tests, and review. Never persisted.
/// Exercises the cases that matter: a near-cap daily key, an uncapped key, a guardrail
/// with three members at differing fractions (so worst-vs-sum is visible), and a
/// policy-only guardrail that must not render a gauge.
nonisolated enum DemoSnapshot {
    static func make(now: Date = Date()) -> OpenRouterSnapshot {
        let monthly = ResetWindowCalculator.window(for: .monthly, now: now)
        let daily = ResetWindowCalculator.window(for: .daily, now: now)

        let members = [
            GuardrailKeyBudget(guardrailID: "g1", keyHash: "h1", keyName: "Production Key",
                               keyLabel: "sk-or-v1-au7...890", spent: 61, limit: 100,
                               usedFraction: 0.61, supersededByKeyLimit: false),
            GuardrailKeyBudget(guardrailID: "g1", keyHash: "h2", keyName: "Worker Key",
                               keyLabel: "sk-or-v1-b12...441", spent: 30, limit: 100,
                               usedFraction: 0.30, supersededByKeyLimit: false),
            GuardrailKeyBudget(guardrailID: "g1", keyHash: "h3", keyName: "Batch Key",
                               keyLabel: "sk-or-v1-c93...077", spent: 12, limit: 100,
                               usedFraction: 0.12, supersededByKeyLimit: false)
        ]

        return OpenRouterSnapshot(
            accountCredit: AccountCredit(totalPurchased: 100, totalUsed: Decimal(string: "25.50")!),
            keyBudgets: [
                KeyBudget(keyHash: "h4", name: "CI Key", label: "sk-or-v1-d44...118",
                          disabled: false, limit: 10, remaining: Decimal(string: "1.80")!,
                          spent: Decimal(string: "8.20")!, window: daily, includesBYOK: false,
                          usedFraction: 0.82, isApproximate: false),
                KeyBudget(keyHash: "h1", name: "Production Key", label: "sk-or-v1-au7...890",
                          disabled: false, limit: 100, remaining: Decimal(string: "39.00")!,
                          spent: 61, window: monthly, includesBYOK: false,
                          usedFraction: 0.61, isApproximate: false)
            ],
            uncappedKeys: [
                KeySpend(keyHash: "h5", name: "Scratch Key", label: "sk-or-v1-e07...903",
                         disabled: false, spentInWindow: Decimal(string: "3.10")!)
            ],
            guardrailBudgets: [
                GuardrailBudget(id: "g1", name: "Production Guardrail", limit: 100,
                                window: monthly, includesBYOK: false, members: members,
                                worstFraction: 0.61),
                GuardrailBudget(id: "g2", name: "Workspace default", limit: 50,
                                window: daily, includesBYOK: false, members: [],
                                worstFraction: 0)
            ],
            guardrailsAvailable: true,
            spentThisMonth: Decimal(string: "108.86")!,
            spentLast30Days: Decimal(string: "130.76")!,
            spentLast15Minutes: Decimal(string: "0.0231")!,
            spentLastHour: Decimal(string: "0.0802")!,
            spentToday: Decimal(string: "3.0647")!,
            spentLast24Hours: Decimal(string: "4.1120")!,
            spentThisWeek: Decimal(string: "24.83")!,
            projectedThisMonth: Decimal(string: "141.20")!,
            recentModels: [
                ModelUsage(model: "z-ai/glm-5.3-flash", spend: Decimal(string: "0.0105")!,
                           tokens: 690_584, requests: 2,
                           lastCalledAt: now.addingTimeInterval(-120)),
                ModelUsage(model: "anthropic/claude-opus-5", spend: Decimal(string: "0.0089")!,
                           tokens: 41_220, requests: 3,
                           lastCalledAt: now.addingTimeInterval(-360)),
                ModelUsage(model: "openai/gpt-5.2-mini", spend: Decimal(string: "0.0037")!,
                           tokens: 1_204_910, requests: 5,
                           lastCalledAt: now.addingTimeInterval(-540))
            ],
            fetchedAt: now
        )
    }
}
