import Foundation
import Testing
@testable import PlanMonitor

/// The console reports money in minor units and omits what does not apply to an account, so the
/// things worth pinning down are the arithmetic of the three sums and the difference between "not
/// reported" and "zero". Both are places where a silent change would misreport money rather than
/// merely look wrong.
///
/// The figures below are the live account of 2026-10-14: $200 available (the promotional grant, no
/// paid credit), $19.94 consumed this month, and an own limit of $200.
struct ClaudePlatformMenuBarDigitsTests {
    private static let live = ClaudePlatformMenuBarDigits.Figures(
        available: 20_000,
        consumed: 1_994,
        userLimit: 20_000,
        currency: "USD"
    )

    private func text(
        _ display: ClaudePlatformMenuBarDisplay,
        _ figures: ClaudePlatformMenuBarDigits.Figures = ClaudePlatformMenuBarDigitsTests.live
    ) -> String? {
        ClaudePlatformMenuBarDigits.resolve(display: display, figures: figures, style: .signAfter).text
    }

    // MARK: - The eight choices

    @Test func everyChoiceReadsTheLiveAccount() {
        #expect(text(.iconOnly) == nil)
        #expect(text(.consumed) == "19$")                 // 19.94, truncated
        #expect(text(.left) == "180$")                    // 200 − 19.94
        // `/` separates two amounts; this provider never shows a percentage.
        #expect(text(.consumedOfAvailable) == "19/200$")
        #expect(text(.leftOfAvailable) == "180/200$")
        #expect(text(.consumedOfUserLimit) == "19/200$")
        #expect(text(.leftUnderUserLimit) == "180$")
        #expect(text(.leftOfUserLimit) == "180/200$")
    }

    @Test func theDefaultIsWhatIsLeftUnderTheOwnLimit() {
        #expect(ClaudePlatformMenuBarDisplay.default == .leftUnderUserLimit)
    }

    @Test func iconOnlyDrawsNoText() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .iconOnly, figures: Self.live, style: .codeAfter)
        #expect(resolved.text == nil)
        #expect(resolved.severityFraction == nil)
    }

    /// Severity is always the *used* fraction of the denominator on show, whatever sense the
    /// digits read in, so tint means one thing everywhere.
    @Test func severityIsUsedAgainstTheChoicesOwnDenominator() {
        let figures = ClaudePlatformMenuBarDigits.Figures(available: 40_000, consumed: 18_000, userLimit: 20_000)
        func severity(_ display: ClaudePlatformMenuBarDisplay) -> Double? {
            ClaudePlatformMenuBarDigits.resolve(display: display, figures: figures, style: .codeAfter).severityFraction
        }
        #expect(severity(.left) == 0.45)
        #expect(severity(.leftOfAvailable) == 0.45)
        #expect(severity(.leftUnderUserLimit) == 0.9)
        #expect(severity(.leftOfUserLimit) == 0.9)
    }

    // MARK: - Overspend

    @Test func whatIsLeftNeverGoesNegative() {
        let over = ClaudePlatformMenuBarDigits.Figures(available: 20_000, consumed: 25_000, userLimit: 20_000, currency: "USD")
        #expect(text(.left, over) == "0$")
        #expect(text(.leftOfAvailable, over) == "0/200$")
        #expect(text(.leftUnderUserLimit, over) == "0$")
        #expect(text(.leftOfUserLimit, over) == "0/200$")
        // The consumed side stays honest: more than everything was spent.
        #expect(text(.consumedOfAvailable, over) == "250/200$")
    }

    // MARK: - Absent versus zero

    @Test func noOwnLimitMeansTheLimitChoicesDrawNothing() {
        // Anthropic's cap is not the maximum the user set, so it never stands in for one.
        let noLimit = ClaudePlatformMenuBarDigits.Figures(available: 20_000, consumed: 1_994, currency: "USD")
        #expect(text(.consumedOfUserLimit, noLimit) == nil)
        #expect(text(.leftUnderUserLimit, noLimit) == nil)
        #expect(text(.leftOfUserLimit, noLimit) == nil)
        #expect(text(.left, noLimit) == "180$")
    }

    @Test func noConsumptionFigureMeansNothingIsComputedFromIt() {
        // `current_spend` failed: "available" alone is not "what is left".
        let noSpend = ClaudePlatformMenuBarDigits.Figures(available: 20_000, userLimit: 20_000)
        for display in ClaudePlatformMenuBarDisplay.allCases {
            #expect(text(display, noSpend) == nil, "\(display.rawValue) needs the consumed sum")
        }
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
        #expect(left(.none) == "180")
        #expect(left(.signBefore) == "$180")
        #expect(left(.signAfter) == "180$")
        #expect(left(.codeBefore) == "USD 180")
        #expect(left(.codeAfter) == "180 USD")
        #expect(CurrencyStyle.default == .signAfter)
    }

    @Test func theCharacterFollowsTheReportedCurrency() {
        var euros = Self.live
        euros.currency = "EUR"
        #expect(ClaudePlatformMenuBarDigits.resolve(display: .left, figures: euros, style: .signAfter).text == "180€")
        #expect(ClaudePlatformMenuBarDigits.resolve(display: .left, figures: euros, style: .codeAfter).text == "180 EUR")
    }

    /// A `/` pair carries its currency once: the bar has no width for it twice.
    @Test func aPairWritesItsCurrencyOnce() {
        func pair(_ style: CurrencyStyle) -> String? {
            ClaudePlatformMenuBarDigits.resolve(display: .leftOfAvailable, figures: Self.live, style: style).text
        }
        #expect(pair(.signAfter) == "180/200$")
        #expect(pair(.codeBefore) == "USD 180/200")
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
        #expect(resolved.text == "180")
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
