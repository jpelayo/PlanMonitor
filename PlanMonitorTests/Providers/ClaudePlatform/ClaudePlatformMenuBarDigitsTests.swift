import Foundation
import Testing
@testable import PlanMonitor

/// The console reports money in minor units and omits what does not apply to an account, so the two
/// things worth pinning down are the unit arithmetic and the difference between "not reported" and
/// "zero". Both are places where a silent change would misreport money rather than merely look
/// wrong.
///
/// The figures below are the real shape seen on a Max account: a $200 promotional grant with $199.54
/// left, 46 cents spent, and one cent of card-paid credit.
struct ClaudePlatformMenuBarDigitsTests {
    private static let live = ClaudePlatformMenuBarDigits.Figures(
        promoRemaining: 19_954,
        promoGranted: 20_000,
        spend: 46,
        spendLimit: 20_000,
        prepaidRemaining: 1,
        invoiced: nil,
        currency: "USD"
    )

    // MARK: - Single indicators

    @Test func promoAmountShowsWholeUnitsOfWhatIsLeft() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .promoAmount, figures: Self.live)
        #expect(resolved.text == "$199")
        // Severity is always the *used* fraction, whatever sense the digits show: 46/20000.
        #expect(resolved.severityFraction == 0.0023)
    }

    @Test func promoPercentShowsWhatIsLeftNotWhatIsUsed() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .promoPercent, figures: Self.live)
        // 19954/20000 = 99.77%, truncated.
        #expect(resolved.text == "99%")
    }

    @Test func spendPercentShowsWhatHasGone() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .spendPercent, figures: Self.live)
        // 46/20000 = 0.23%, truncated to zero — correct, and the amount form is there for detail.
        #expect(resolved.text == "0%")
    }

    @Test func iconOnlyDrawsNoText() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .iconOnly, figures: Self.live)
        #expect(resolved.text == nil)
        #expect(resolved.severityFraction == nil)
    }

    // MARK: - Pairs

    @Test func pairsJoinWithAMiddleDotInSelectionOrder() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .promoAndSpendAmount, figures: Self.live)
        #expect(resolved.text == "$199\u{00B7}$0")
    }

    @Test func percentPairKeepsEachIndicatorsOwnSense() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .promoAndSpendPercent, figures: Self.live)
        // Credit left, spend gone — deliberately not the same sense.
        #expect(resolved.text == "99%\u{00B7}0%")
    }

    @Test func severityTakesTheTightestGaugeOnShow() {
        let figures = ClaudePlatformMenuBarDigits.Figures(
            promoRemaining: 10_000, promoGranted: 20_000,   // 50% used
            spend: 18_000, spendLimit: 20_000               // 90% used
        )
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .promoAndSpendAmount, figures: figures)
        #expect(resolved.severityFraction == 0.9)
    }

    // MARK: - Absent versus zero

    @Test func anUnreportedFigureIsDroppedRatherThanPrintedAsZero() {
        // A pre-paid account has nothing to invoice. Printing "$0" would claim a fact the console
        // never reported.
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .invoicedAmount, figures: Self.live)
        #expect(resolved.text == nil)
    }

    @Test func aPairFallsBackToWhicheverHalfReports() {
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .spendAndInvoicedAmount, figures: Self.live)
        #expect(resolved.text == "$0")
    }

    @Test func noIndicatorSubstitutesForAnother() {
        // Only promotional credit is reported; asking for prepaid must not quietly show it.
        let promoOnly = ClaudePlatformMenuBarDigits.Figures(promoRemaining: 19_954, promoGranted: 20_000)
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .prepaidAmount, figures: promoOnly)
        #expect(resolved.text == nil)
    }

    @Test func everyDisplaySurvivesAnEmptySnapshot() {
        let empty = ClaudePlatformMenuBarDigits.Figures()
        for display in ClaudePlatformMenuBarDisplay.allCases {
            let resolved = ClaudePlatformMenuBarDigits.resolve(display: display, figures: empty)
            #expect(resolved.text == nil, "\(display.rawValue) should draw nothing with no data")
            #expect(resolved.severityFraction == nil)
        }
    }

    @Test func residueReadsAsZeroButStillReports() {
        // One cent of card-paid credit is rounding residue, not money — it shows as zero, and
        // crucially it is not confused with "no prepaid balance at all".
        let resolved = ClaudePlatformMenuBarDigits.resolve(display: .prepaidAmount, figures: Self.live)
        #expect(resolved.text == "$0")
    }

    // MARK: - Money formatting

    @Test func amountsTruncateTowardZeroRatherThanRounding() {
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 19_999, currency: "USD") == "$199")
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 20_000, currency: "USD") == "$200")
    }

    @Test func fiveFigureAmountsUseTheKForm() {
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 1_250_000, currency: "USD") == "$12.5k")
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 15_000_000, currency: "USD") == "$150k")
    }

    @Test func aNonUSDCurrencyKeepsItsCode() {
        #expect(ClaudePlatformMoney.formatMenuBar(minorUnits: 19_954, currency: "EUR") == "199 EUR")
    }

    @Test func theDropdownFormCarriesCentsAndCurrency() {
        #expect(ClaudePlatformMoney.format(minorUnits: 19_954, currency: "USD") == "199.54 USD")
        #expect(ClaudePlatformMoney.format(minorUnits: 0, currency: "USD") == "0.00 USD")
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
