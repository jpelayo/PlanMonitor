import Foundation
import Testing
@testable import PlanMonitor

/// The console reports money in minor units and omits what does not apply to an account, so the
/// things worth pinning down are where each choice reads its figure from, and the difference
/// between "not reported" and "zero". Both are places where a silent change would misreport money
/// rather than merely look wrong — as "available minus consumed" did on 2026-11-01, reading 199$
/// for an account holding 31.87$.
///
/// The figures below are that account: a $200 promotional grant with $31.87 left (the rest used in
/// October), no paid credit, $0.02 spent in November, an own limit of $200, pre-paid with
/// auto-payment off.
struct ClaudePlatformMenuBarDigitsTests {
    private static let live = ClaudePlatformMenuBarDigits.Figures(
        promoGranted: 20_000,
        promoLeft: 3_187,
        prepaidLeft: 0,
        spent: 2,
        userLimit: 20_000,
        spendingStopsAtCredit: true,
        currency: "USD"
    )

    private func text(
        _ display: ClaudePlatformMenuBarDisplay,
        _ figures: ClaudePlatformMenuBarDigits.Figures = ClaudePlatformMenuBarDigitsTests.live
    ) -> String? {
        ClaudePlatformMenuBarDigits.resolve(display: display, figures: figures, style: .signAfter).text
    }

    // MARK: - The choices

    @Test func everyChoiceReadsTheLiveAccount() {
        #expect(text(.iconOnly) == nil)
        // Credit, from the balances.
        #expect(text(.left) == "31$")                     // 31.87, truncated
        // `/` separates two amounts; this provider never shows a percentage.
        #expect(text(.leftOfAvailable) == "31/200$")
        #expect(text(.consumedOfAvailable) == "168/200$")
        #expect(text(.promoLeft) == "31$")
        #expect(text(.prepaidLeft) == "0$")
        // Spend, against the own limit — capped at the credit a pre-paid account holds.
        #expect(text(.leftUnderUserLimit) == "31$")
        #expect(text(.leftOfUserLimit) == "31/200$")
        #expect(text(.consumed) == "0$")
        #expect(text(.consumedOfUserLimit) == "0/200$")
        // Nothing to invoice on a pre-paid account.
        #expect(text(.pendingInvoice) == nil)
    }

    @Test func theDefaultIsWhatIsLeftToSpend() {
        #expect(ClaudePlatformMenuBarDisplay.default == .leftUnderUserLimit)
    }

    /// A saved choice from the 2026-10-14 list must still be found.
    @Test func theOldRawValuesSurvive() {
        let saved = ["iconOnly", "consumed", "left", "consumedOfAvailable", "leftOfAvailable",
                     "consumedOfUserLimit", "leftUnderUserLimit", "leftOfUserLimit"]
        for raw in saved {
            #expect(ClaudePlatformMenuBarDisplay(rawValue: raw) != nil, "\(raw)")
        }
    }

    @Test func iconOnlyDrawsNoText() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .iconOnly, figures: Self.live, style: .codeAfter)
        #expect(resolved.text == nil)
        #expect(resolved.severityFraction == nil)
    }

    // MARK: - The cap

    /// Only a pre-paid account without auto-payment stops at its credit. Invoiced or topped up
    /// automatically, the room under the limit is the figure.
    @Test func leftToSpendIsCappedOnlyWhenSpendingStopsAtTheCredit() {
        #expect(text(.leftUnderUserLimit) == "31$")

        var invoiced = Self.live
        invoiced.pendingInvoice = 1_234
        invoiced.spendingStopsAtCredit = false
        #expect(text(.leftUnderUserLimit, invoiced) == "199$")
        #expect(text(.leftOfUserLimit, invoiced) == "199/200$")
        #expect(text(.pendingInvoice, invoiced) == "12$")

        var autoPaid = Self.live
        autoPaid.spendingStopsAtCredit = false
        #expect(text(.leftUnderUserLimit, autoPaid) == "199$")
    }

    @Test func unknownCreditIsNoCap() {
        // `prepaid/credits` failed: what is left to spend is the room under the limit.
        let noCredit = ClaudePlatformMenuBarDigits.Figures(spent: 2, userLimit: 20_000, spendingStopsAtCredit: true, currency: "USD")
        #expect(text(.leftUnderUserLimit, noCredit) == "199$")
        #expect(text(.left, noCredit) == nil)
    }

    // MARK: - Severity

    /// Severity is always the *used* fraction of the denominator on show, whatever sense the
    /// digits read in, so tint means one thing everywhere.
    @Test func severityIsUsedAgainstTheChoicesOwnDenominator() {
        let figures = ClaudePlatformMenuBarDigits.Figures(
            promoGranted: 40_000, promoLeft: 22_000, prepaidLeft: 0, spent: 18_000, userLimit: 20_000
        )
        func severity(_ display: ClaudePlatformMenuBarDisplay, _ figures: ClaudePlatformMenuBarDigits.Figures) -> Double? {
            ClaudePlatformMenuBarDigits.resolve(display: display, figures: figures, style: .codeAfter).severityFraction
        }
        #expect(severity(.left, figures) == 0.45)
        #expect(severity(.leftOfAvailable, figures) == 0.45)
        #expect(severity(.consumedOfAvailable, figures) == 0.45)
        #expect(severity(.promoLeft, figures) == 0.45)
        #expect(severity(.prepaidLeft, figures) == nil)
        #expect(severity(.leftUnderUserLimit, figures) == 0.9)
        #expect(severity(.leftOfUserLimit, figures) == 0.9)
        #expect(severity(.consumed, figures) == 0.9)
        #expect(severity(.consumedOfUserLimit, figures) == 0.9)

        // When the credit binds, the tint follows it: $10 left of a $200 limit is 95% gone.
        var capped = figures
        capped.promoLeft = 1_000
        capped.spendingStopsAtCredit = true
        #expect(severity(.leftUnderUserLimit, capped) == 0.95)
    }

    // MARK: - Overspend

    @Test func whatIsLeftNeverGoesNegative() {
        let over = ClaudePlatformMenuBarDigits.Figures(
            promoGranted: 20_000, promoLeft: 0, prepaidLeft: 0, spent: 25_000, userLimit: 20_000, currency: "USD"
        )
        #expect(text(.left, over) == "0$")
        #expect(text(.leftOfAvailable, over) == "0/200$")
        #expect(text(.leftUnderUserLimit, over) == "0$")
        #expect(text(.leftOfUserLimit, over) == "0/200$")
        // The spend side stays honest: more than the limit was spent.
        #expect(text(.consumedOfUserLimit, over) == "250/200$")
    }

    // MARK: - Absent versus zero

    @Test func noOwnLimitMeansTheLimitChoicesDrawNothing() {
        // Anthropic's cap is not the maximum the user set, so it never stands in for one.
        var noLimit = Self.live
        noLimit.userLimit = nil
        #expect(text(.consumedOfUserLimit, noLimit) == nil)
        #expect(text(.leftUnderUserLimit, noLimit) == nil)
        #expect(text(.leftOfUserLimit, noLimit) == nil)
        #expect(text(.consumed, noLimit) == "0$")
        #expect(text(.left, noLimit) == "31$")
    }

    @Test func creditChoicesNeedNoSpendFigure() {
        // `current_spend` failed: the balances still say what is held; nothing about spending does.
        var noSpend = Self.live
        noSpend.spent = nil
        #expect(text(.left, noSpend) == "31$")
        #expect(text(.consumedOfAvailable, noSpend) == "168/200$")
        for display in [ClaudePlatformMenuBarDisplay.leftUnderUserLimit, .leftOfUserLimit, .consumed, .consumedOfUserLimit] {
            #expect(text(display, noSpend) == nil, "\(display.rawValue) needs this month's spend")
        }
    }

    @Test func prepaidCreditAloneIsCredit() {
        let prepaidOnly = ClaudePlatformMenuBarDigits.Figures(prepaidLeft: 5_000, currency: "USD")
        #expect(text(.left, prepaidOnly) == "50$")
        #expect(text(.leftOfAvailable, prepaidOnly) == "50/50$")
        #expect(text(.prepaidLeft, prepaidOnly) == "50$")
        #expect(text(.promoLeft, prepaidOnly) == nil)
    }

    @Test func everyDisplaySurvivesAnEmptySnapshot() {
        let empty = ClaudePlatformMenuBarDigits.Figures()
        for display in ClaudePlatformMenuBarDisplay.allCases {
            let resolved = ClaudePlatformMenuBarDigits.resolve(display: display, figures: empty, style: .codeAfter)
            #expect(resolved.text == nil, "\(display.rawValue) should draw nothing with no data")
            #expect(resolved.severityFraction == nil)
        }
    }

    // MARK: - Money formatting

    @Test func amountsTruncateTowardZeroRatherThanRounding() {
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 19_999, currency: "USD", style: .codeAfter) == "199 USD")
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 20_000, currency: "USD", style: .codeAfter) == "200 USD")
    }

    @Test func fiveFigureAmountsUseTheKForm() {
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 1_250_000, currency: "USD", style: .codeAfter) == "12.5k USD")
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 15_000_000, currency: "USD", style: .codeAfter) == "150k USD")
    }

    /// Platform rule: never more than two decimals, never a thousands separator.
    @Test func aFinerExponentStillPrintsTwoDecimals() {
        #expect(ClaudePlatformMoney.formatValue(minorUnits: 12_340, exponent: 3) == "12.34")
        #expect(ClaudePlatformMoney.formatValue(minorUnits: 123_456_789) == "1234567.89")
    }

    @Test func theDropdownFormCarriesCentsAndCurrency() {
        #expect(ClaudePlatformMoney.format(minorUnits: 19_954, currency: "USD", style: .codeAfter) == "199.54 USD")
        #expect(ClaudePlatformMoney.format(minorUnits: 0, currency: "USD", style: .codeAfter) == "0.00 USD")
    }

    @Test func everyCurrencyStyleOnTheBar() {
        func left(_ style: CurrencyStyle) -> String? {
            ClaudePlatformMenuBarDigits.resolve(display: .left, figures: Self.live, style: style).text
        }
        // The user's words: the character is `$`, flush; the symbol is `USD`, spaced.
        #expect(left(.none) == "31")
        #expect(left(.signBefore) == "$31")
        #expect(left(.signAfter) == "31$")
        #expect(left(.codeBefore) == "USD 31")
        #expect(left(.codeAfter) == "31 USD")
        #expect(CurrencyStyle.default == .signAfter)
    }

    @Test func theCharacterFollowsTheReportedCurrency() {
        var euros = Self.live
        euros.currency = "EUR"
        #expect(ClaudePlatformMenuBarDigits.resolve(display: .left, figures: euros, style: .signAfter).text == "31€")
        #expect(ClaudePlatformMenuBarDigits.resolve(display: .left, figures: euros, style: .codeAfter).text == "31 EUR")
    }

    /// A `/` pair carries its currency once: the bar has no width for it twice.
    @Test func aPairWritesItsCurrencyOnce() {
        func pair(_ style: CurrencyStyle) -> String? {
            ClaudePlatformMenuBarDigits.resolve(display: .leftOfAvailable, figures: Self.live, style: style).text
        }
        #expect(pair(.signAfter) == "31/200$")
        #expect(pair(.codeBefore) == "USD 31/200")
    }

    @Test func aDeficitKeepsItsMinusOutermost() {
        #expect(CurrencyStyle.signBefore.apply(to: "-4", currency: "USD") == "-$4")
        #expect(CurrencyStyle.codeBefore.apply(to: "-4", currency: "USD") == "-USD 4")
        #expect(CurrencyStyle.signAfter.apply(to: "-4", currency: "USD") == "-4$")
    }

    @Test func noReportedCurrencyMeansBareAmounts() {
        var figures = Self.live
        figures.currency = nil
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .left, figures: figures, style: .codeAfter)
        #expect(resolved.text == "31")
    }

    @Test func absentBalancesStayAbsentThroughNormalisation() {
        #expect(ClaudePlatformMoney.normalizedBalance(nil) == nil)
        #expect(ClaudePlatformMoney.normalizedBalance(1) == 0)
        #expect(ClaudePlatformMoney.normalizedBalance(-500) == 0)
        #expect(ClaudePlatformMoney.normalizedBalance(19_954) == 19_954)
    }

    @Test func aMissingOrZeroDenominatorYieldsNoFraction() {
        #expect(ClaudePlatformMoney.usedFraction(used: 46, limit: nil) == nil)
        #expect(ClaudePlatformMoney.usedFraction(used: 46, limit: 0) == nil)
        #expect(ClaudePlatformMoney.usedFraction(used: nil, limit: 20_000) == nil)
    }

    @Test func overspendIsNotClampedAwayByTheModel() {
        // The view pins the gauge full; the number itself must stay honest so severity can see it.
        let fraction = ClaudePlatformMoney.usedFraction(used: 30_000, limit: 20_000)
        #expect(fraction == 1.5)
    }
}
