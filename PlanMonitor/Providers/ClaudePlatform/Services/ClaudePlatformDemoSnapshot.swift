import Foundation

/// Deterministic App Review data: the console account captured on 2026-10-09, with its dates moved
/// relative to `now` so the countdowns read sensibly whenever the demo runs. Every row the dropdown
/// can draw for a pre-paid account is populated — `ClaudePlatformDemoTests` holds it to that.
nonisolated enum ClaudePlatformDemoSnapshot {
    static func snapshot(now: Date = Date()) -> ClaudePlatformSnapshot {
        ClaudePlatformSnapshot(
            currency: "USD",
            exponent: 2,
            promoGranted: 20_000,               // $200.00
            promoRemaining: 19_954,             // $199.54
            promoExpiresAt: now.addingTimeInterval(23 * 24 * 3600),
            promoName: "API credit (Max 20x)",
            prepaidRemaining: 0,
            pendingInvoice: nil,                // pre-paid: nothing to invoice
            spendUsed: 46,                      // $0.46
            spendResetsAt: now.addingTimeInterval(20 * 24 * 3600),
            enforcedSpendLimit: 50_000,         // $500.00
            selfSelectedLimits: [
                .init(amount: 19_500, action: .notifyOnly),
                .init(amount: 20_000, action: .notifyAndPause)
            ],
            autoRecharge: .init(isEnabled: false, targetAmount: 1_500, thresholdAmount: 500),
            currencyMismatch: false
        )
    }

    static let identityLabel = "demo@example.com"
    static let organizationName = "Demo Organization"
}
