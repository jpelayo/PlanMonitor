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
        let snapshot = ClaudePlatformBilling.assemble(credits: credits, spend: nil, limits: nil, autoRecharge: nil)
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
        #expect(ClaudePlatformBilling.assemble(credits: nil, spend: nil, limits: nil, autoRecharge: unknown).autoRecharge == nil)
        #expect(ClaudePlatformBilling.assemble(credits: nil, spend: nil, limits: nil, autoRecharge: enabled).autoRecharge?.isEnabled == true)
    }

    // MARK: - Missing and odd figures

    @Test func nothingReportedIsEmptyNotZero() {
        let snapshot = ClaudePlatformBilling.assemble(credits: nil, spend: nil, limits: nil, autoRecharge: nil)
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
        let snapshot = ClaudePlatformBilling.assemble(credits: nil, spend: spend, limits: limits, autoRecharge: nil)

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
        let snapshot = ClaudePlatformBilling.assemble(credits: credits, spend: nil, limits: nil, autoRecharge: nil)
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
        let snapshot = ClaudePlatformBilling.assemble(credits: credits, spend: nil, limits: nil, autoRecharge: nil)

        #expect(snapshot.promoGranted == 25_000)
        #expect(snapshot.promoRemaining == 15_000)
        // The zero-grant tranche is not credit, so its earlier date does not count.
        #expect(snapshot.promoExpiresAt == ClaudePlatformFixtures.date("2026-11-15T00:00:00Z"))
    }

    // MARK: - Money formatting

    @Test func theStatedExponentIsHonoured() throws {
        let credits = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self,
            #"{"amount":500,"currency":"jpy","balance":{"credits":{"amount_minor":500,"exponent":0}}}"#
        )
        let snapshot = ClaudePlatformBilling.assemble(credits: credits, spend: nil, limits: nil, autoRecharge: nil)

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
        #expect(ClaudePlatformBilling.assemble(credits: fromTranche, spend: nil, limits: nil, autoRecharge: nil).currency == "EUR")

        let none = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self,
            #"{"promo_tranches":[{"remaining_amount_minor_units":100,"granted_amount_minor_units":200}]}"#
        )
        let snapshot = ClaudePlatformBilling.assemble(credits: none, spend: nil, limits: nil, autoRecharge: nil)
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

    @Test func theMenuBarReadsTheCapturedAccount() throws {
        let figures = try ClaudePlatformFixtures.capturedSnapshot().figures
        // One sum of available (the $200 grant + $0 paid), one of consumed (this month's $0.46).
        #expect(figures.available == 20_000)
        #expect(figures.consumed == 46)
        #expect(figures.userLimit == 20_000)
        #expect(ClaudePlatformMenuBarDigits.resolve(display: .left, figures: figures, style: .signAfter).text == "199$")
        #expect(ClaudePlatformMenuBarDigits.resolve(display: .consumed, figures: figures, style: .signAfter).text == "0$")
        #expect(ClaudePlatformMenuBarDigits.resolve(display: .leftOfUserLimit, figures: figures, style: .signAfter).text == "199/200$")
    }

    /// Paid credit joins the one sum of available; neither half reported means no sum at all.
    @Test func totalAvailableIsPromotionalPlusPaidCredit() throws {
        var snapshot = try ClaudePlatformFixtures.capturedSnapshot()
        snapshot.prepaidRemaining = 5_000
        #expect(snapshot.totalAvailable == 25_000)

        snapshot.promoGranted = nil
        snapshot.promoRemaining = nil
        #expect(snapshot.totalAvailable == 5_000)

        snapshot.prepaidRemaining = nil
        #expect(snapshot.totalAvailable == nil)
    }
}
