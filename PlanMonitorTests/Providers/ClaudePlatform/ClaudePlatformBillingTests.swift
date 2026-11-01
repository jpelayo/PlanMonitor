import Foundation
import Testing
@testable import PlanMonitor

/// The money model, from the captured responses to what the dropdown, the ring and the menu bar
/// draw. "Not reported" must never read as zero, and nothing may be borrowed from the claude.ai
/// subscription org's model.
@Suite("Claude-API billing")
struct ClaudePlatformBillingTests {

    // MARK: - The captured account

    @Test func capturedAccountAssemblesAsTheConsoleShowsIt() throws {
        let snapshot = try ClaudePlatformFixtures.capturedSnapshot()

        #expect(snapshot.currency == "USD")
        #expect(snapshot.exponent == 2)
        #expect(snapshot.promoGranted == 20_000)
        #expect(snapshot.promoRemaining == 19_954)
        #expect(snapshot.promoExpiresAt == ClaudePlatformFixtures.date("2026-11-04T00:00:00Z"))
        #expect(snapshot.promoName == "API credit (Max 20x)")
        #expect(snapshot.spendUsed == 46)
        #expect(snapshot.spendResetsAt == ClaudePlatformFixtures.date("2026-11-01T00:00:00Z"))
        #expect(snapshot.enforcedSpendLimit == 50_000)
        #expect(snapshot.selfSelectedLimits == [
            .init(amount: 19_500, action: .notifyOnly),
            .init(amount: 20_000, action: .notifyAndPause)
        ])
        #expect(snapshot.notifyLimit == 19_500)
        #expect(snapshot.pauseLimit == 20_000)
        #expect(snapshot.currencyMismatch == false)
    }

    /// `amount` is 19955 and the promo tranche 19954. The difference is not card-paid credit:
    /// `amount_without_scoped_credits` says 0, and that field — never the subtraction — is read.
    @Test func theOneCentGapIsNotCardPaidCredit() throws {
        let snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        #expect(snapshot.prepaidRemaining == 0)
    }

    @Test func withoutTheExplicitFieldPrepaidIsUnknownNotDerived() throws {
        let credits = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self,
            #"{"amount":19955,"currency":"USD","promo_tranches":[{"remaining_amount_minor_units":19954,"granted_amount_minor_units":20000,"currency":"USD"}]}"#
        )
        let snapshot = ClaudePlatformBilling.assemble(credits: credits, spend: nil, limits: nil, autoRecharge: nil, now: ClaudePlatformFixtures.capturedAt)
        #expect(snapshot.prepaidRemaining == nil)
    }

    /// `pending_invoice_amount_cents: null` on a pre-paid account: the row is absent, not $0.
    @Test func nullInvoiceStaysNil() throws {
        let snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        #expect(snapshot.pendingInvoice == nil)
    }

    @Test func autoPaymentComesFromAutoRechargeNotAutoReloadSettings() throws {
        // `prepaid/credits` says `auto_reload_settings: null`; reading that would give "unknown".
        let snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        #expect(snapshot.autoRecharge == .init(isEnabled: false, targetAmount: 1_500, thresholdAmount: 500))
    }

    @Test func unknownAutoRechargeStatusIsNotGuessed() throws {
        let unknown = try ClaudePlatformFixtures.decode(
            ClaudePlatformAutoRechargeResponse.self, #"{"status":"pending_verification"}"#
        )
        let enabled = try ClaudePlatformFixtures.decode(
            ClaudePlatformAutoRechargeResponse.self, #"{"status":"enabled","target_amount":2000,"threshold_amount":1000}"#
        )
        let at = ClaudePlatformFixtures.capturedAt
        #expect(ClaudePlatformBilling.assemble(credits: nil, spend: nil, limits: nil, autoRecharge: unknown, now: at).autoRecharge == nil)
        #expect(ClaudePlatformBilling.assemble(credits: nil, spend: nil, limits: nil, autoRecharge: enabled, now: at).autoRecharge?.isEnabled == true)
    }

    // MARK: - Missing and odd figures

    @Test func nothingReportedIsEmptyNotZero() {
        let snapshot = ClaudePlatformBilling.assemble(credits: nil, spend: nil, limits: nil, autoRecharge: nil, now: ClaudePlatformFixtures.capturedAt)
        #expect(snapshot.isEmpty)
        #expect(snapshot.promoUsedFraction == nil)
        #expect(snapshot.spendUsedFraction == nil)
    }

    /// The headline gauge's denominator missing must degrade the row, not invent one.
    @Test func missingEnforcedLimitLeavesSpendWithoutAGauge() throws {
        let limits = try ClaudePlatformFixtures.decode(
            ClaudePlatformSpendLimitsResponse.self, #"{"spend_limits":[],"enforced_limit_usd":null}"#
        )
        let spend = try ClaudePlatformFixtures.decode(ClaudePlatformCurrentSpendResponse.self, ClaudePlatformFixtures.currentSpend)
        let snapshot = ClaudePlatformBilling.assemble(credits: nil, spend: spend, limits: limits, autoRecharge: nil, now: ClaudePlatformFixtures.capturedAt)

        #expect(snapshot.spendUsed == 46)
        #expect(snapshot.enforcedSpendLimit == nil)
        #expect(snapshot.spendUsedFraction == nil)
        #expect(ClaudePlatformRingSource.spend.fill(for: snapshot) == nil)
    }

    @Test func aTrancheInAnotherCurrencyIsFlagged() throws {
        let credits = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self,
            #"{"amount":100,"currency":"USD","promo_tranches":[{"remaining_amount_minor_units":50,"granted_amount_minor_units":100,"currency":"EUR"}]}"#
        )
        let snapshot = ClaudePlatformBilling.assemble(credits: credits, spend: nil, limits: nil, autoRecharge: nil, now: ClaudePlatformFixtures.capturedAt)
        #expect(snapshot.currencyMismatch)
    }

    @Test func tranchesAreSummedAndTheEarliestExpiryWins() throws {
        let credits = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self,
            #"""
            {"amount":15000,"currency":"USD","amount_without_scoped_credits":0,"promo_tranches":[
              {"remaining_amount_minor_units":10000,"granted_amount_minor_units":20000,"currency":"USD","expires_at":"2026-12-01T00:00:00Z","name":"Later"},
              {"remaining_amount_minor_units":5000,"granted_amount_minor_units":5000,"currency":"USD","expires_at":"2026-11-15T00:00:00Z","name":"Sooner"},
              {"remaining_amount_minor_units":0,"granted_amount_minor_units":0,"currency":"USD","expires_at":"2026-10-20T00:00:00Z"}
            ]}
            """#
        )
        let snapshot = ClaudePlatformBilling.assemble(credits: credits, spend: nil, limits: nil, autoRecharge: nil, now: ClaudePlatformFixtures.capturedAt)

        #expect(snapshot.promoGranted == 25_000)
        #expect(snapshot.promoRemaining == 15_000)
        // The zero-grant tranche is not credit, so its earlier date does not count.
        #expect(snapshot.promoExpiresAt == ClaudePlatformFixtures.date("2026-11-15T00:00:00Z"))

        // Once "Sooner" has expired, only "Later" is credit.
        let later = ClaudePlatformBilling.assemble(
            credits: credits, spend: nil, limits: nil, autoRecharge: nil,
            now: ClaudePlatformFixtures.date("2026-11-20T00:00:00Z")
        )
        #expect(later.promoGranted == 20_000)
        #expect(later.promoRemaining == 10_000)
        #expect(later.promoExpiresAt == ClaudePlatformFixtures.date("2026-12-01T00:00:00Z"))
    }

    /// A grant past its expiry is not credit, whether or not the console still lists it.
    @Test func anExpiredGrantIsNotCredit() throws {
        let credits = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self, ClaudePlatformFixtures.prepaidCredits
        )
        func assembled(at iso: String) -> ClaudePlatformSnapshot {
            ClaudePlatformBilling.assemble(
                credits: credits, spend: nil, limits: nil, autoRecharge: nil,
                now: ClaudePlatformFixtures.date(iso)
            )
        }

        let before = assembled(at: "2026-11-03T23:59:59Z")
        #expect(before.promoRemaining == 19_954)
        #expect(before.figures.creditLeft == 19_954)

        let after = assembled(at: "2026-11-04T00:00:01Z")
        #expect(after.promoGranted == nil)
        #expect(after.promoRemaining == nil)
        // The prepaid balance is still reported, so credit is a real zero, not unknown.
        #expect(after.figures.creditLeft == 0)
        #expect(ClaudePlatformRingSource.promo.fill(for: after) == nil)
    }

    // MARK: - Money formatting

    @Test func theStatedExponentIsHonoured() throws {
        let credits = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self,
            #"{"amount":500,"currency":"jpy","balance":{"credits":{"amount_minor":500,"exponent":0}}}"#
        )
        let snapshot = ClaudePlatformBilling.assemble(credits: credits, spend: nil, limits: nil, autoRecharge: nil, now: ClaudePlatformFixtures.capturedAt)

        #expect(snapshot.currency == "JPY")
        #expect(snapshot.exponent == 0)
        #expect(snapshot.format(500, style: .codeAfter) == "500 JPY")
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 500, currency: "JPY", exponent: 0, style: .codeAfter) == "500 JPY")
    }

    /// Both menu-bar forms truncate: 99,960 must not round up to "100.0k".
    @Test func theThousandsFormTruncates() {
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 9_996_000, currency: "USD", style: .codeAfter) == "99.9k USD")
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 19_999_900, currency: "USD", style: .signBefore) == "$199k")
    }

    /// No currency is assumed: the grants' own is used when the account names none, and with
    /// neither the amounts are written bare whatever the style.
    @Test func theCurrencyComesFromTheAPIOrNowhere() throws {
        let fromTranche = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self,
            #"{"promo_tranches":[{"remaining_amount_minor_units":100,"granted_amount_minor_units":200,"currency":"eur"}]}"#
        )
        #expect(ClaudePlatformBilling.assemble(credits: fromTranche, spend: nil, limits: nil, autoRecharge: nil, now: ClaudePlatformFixtures.capturedAt).currency == "EUR")

        let none = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self,
            #"{"promo_tranches":[{"remaining_amount_minor_units":100,"granted_amount_minor_units":200}]}"#
        )
        let snapshot = ClaudePlatformBilling.assemble(credits: none, spend: nil, limits: nil, autoRecharge: nil, now: ClaudePlatformFixtures.capturedAt)
        #expect(snapshot.currency == nil)
        #expect(snapshot.format(100, style: .codeAfter) == "1.00")
        #expect(snapshot.format(100, style: .signBefore) == "1.00")
        #expect(!snapshot.currencyMismatch)
    }

    // MARK: - Gauges and ring

    @Test func gaugesShowUsedFractions() throws {
        let snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        #expect(try #require(snapshot.promoUsedFraction) == 46.0 / 20_000.0)
        // Against the account's own $200 limit, not Anthropic's $500 cap.
        #expect(try #require(snapshot.spendUsedFraction) == 46.0 / 20_000.0)
    }

    /// The spend ceiling is the account's own `notify_and_pause` limit, else Anthropic's cap; a
    /// `notify_only` limit never is one.
    @Test func spendCeilingIsTheOwnLimitElseAnthropics() throws {
        let captured = try ClaudePlatformFixtures.capturedSnapshot()
        #expect(captured.spendCeiling == 20_000)
        #expect(captured.figures.userLimit == 20_000)

        var notifyOnly = captured
        notifyOnly.selfSelectedLimits = [.init(amount: 19_500, action: .notifyOnly)]
        #expect(notifyOnly.spendCeiling == 50_000)
        // The gauge falls back to Anthropic's cap; the menu bar's "your limit" does not.
        #expect(notifyOnly.figures.userLimit == nil)

        var noCap = captured
        noCap.enforcedSpendLimit = nil
        #expect(noCap.spendCeiling == 20_000)

        var neither = notifyOnly
        neither.enforcedSpendLimit = nil
        #expect(neither.spendCeiling == nil)
        #expect(neither.spendUsedFraction == nil)
    }

    @Test func ringsFillWithWhatIsLeft() throws {
        let snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        #expect(ClaudePlatformRingSource.off.fill(for: snapshot) == nil)
        // 19954/20000 and 1 − 46/20000 both quantise to a whole ring.
        #expect(ClaudePlatformRingSource.promo.fill(for: snapshot) == 1)
        #expect(ClaudePlatformRingSource.spend.fill(for: snapshot) == 1)

        var half = snapshot
        half.promoRemaining = 10_000
        #expect(ClaudePlatformRingSource.promo.fill(for: half) == 0.5)
    }

    private func bar(_ display: ClaudePlatformMenuBarDisplay, _ snapshot: ClaudePlatformSnapshot) -> String? {
        ClaudePlatformMenuBarDigits.resolve(display: display, figures: snapshot.figures, style: .signAfter).text
    }

    @Test func theMenuBarReadsTheCapturedAccount() throws {
        let snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        let figures = snapshot.figures
        // The balances themselves: $199.54 of the $200 grant left, $0 paid; this month's $0.46 spent.
        #expect(figures.creditLeft == 19_954)
        #expect(figures.creditTotal == 20_000)
        #expect(figures.creditUsed == 46)
        #expect(figures.spent == 46)
        #expect(figures.userLimit == 20_000)
        // Pre-paid, auto-payment off.
        #expect(figures.spendingStopsAtCredit)
        #expect(bar(.left, snapshot) == "199$")
        #expect(bar(.consumedOfAvailable, snapshot) == "0/200$")
        #expect(bar(.consumed, snapshot) == "0$")
        #expect(bar(.leftOfUserLimit, snapshot) == "199/200$")
    }

    /// The user's account on 2026-11-01: $168.13 of the grant used in October, $0.02 spent in
    /// November. Grant minus this month's spend read 199$; the credit held is $31.87.
    @Test func creditUsedInEarlierMonthsIsNotGivenBack() throws {
        var snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        snapshot.promoRemaining = 3_187
        snapshot.spendUsed = 2
        #expect(bar(.left, snapshot) == "31$")
        #expect(bar(.consumedOfAvailable, snapshot) == "168/200$")
        // The default: room under the $200 limit, capped at the credit a pre-paid account holds.
        #expect(bar(.leftUnderUserLimit, snapshot) == "31$")
    }

    /// Credit is the balances: promotional left plus prepaid, against the grant plus prepaid.
    /// Neither half reported means no credit figure at all.
    @Test func creditIsPromotionalPlusPaidBalance() throws {
        var snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        snapshot.prepaidRemaining = 5_000
        #expect(snapshot.figures.creditLeft == 24_954)
        #expect(snapshot.figures.creditTotal == 25_000)
        #expect(snapshot.figures.creditUsed == 46)

        snapshot.promoGranted = nil
        snapshot.promoRemaining = nil
        #expect(snapshot.figures.creditLeft == 5_000)
        #expect(snapshot.figures.creditTotal == 5_000)

        snapshot.prepaidRemaining = nil
        #expect(snapshot.figures.creditLeft == nil)
        #expect(snapshot.figures.creditTotal == nil)
    }

    /// Only a pre-paid account that is not topped up automatically stops at its credit.
    @Test func spendingStopsAtCreditOnlyWithoutInvoicingOrAutoPayment() {
        var snapshot = ClaudePlatformSnapshot.empty
        // Auto-payment not reported counts as off.
        #expect(snapshot.spendingStopsAtCredit)

        snapshot.autoRecharge = .init(isEnabled: true, targetAmount: nil, thresholdAmount: nil)
        #expect(!snapshot.spendingStopsAtCredit)

        snapshot.autoRecharge = .init(isEnabled: false, targetAmount: nil, thresholdAmount: nil)
        #expect(snapshot.spendingStopsAtCredit)

        snapshot.pendingInvoice = 0
        #expect(!snapshot.spendingStopsAtCredit)
    }
}
