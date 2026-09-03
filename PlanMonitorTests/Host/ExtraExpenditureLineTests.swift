import Foundation
import Testing
@testable import PlanTracker

@MainActor
struct ExtraExpenditureLineTests {
    // Built from the same localized pieces the view uses so the assertions hold in every
    // host language; the English rendering is "Extra expenditure: Enabled (13.59 USD / 50.00 USD)".
    private static let title = String(localized: "Extra expenditure")
    private static let enabled = String(localized: "Enabled")
    private static let disabled = String(localized: "Disabled")

    @Test func hiddenWhenTheProviderSaysNothingAboutExtraSpend() {
        #expect(ExtraExpenditureLine.text(enabled: nil, hasStartedSpend: true, usedFormatted: "13.59 USD", limitFormatted: "50.00 USD") == nil)
        #expect(ExtraExpenditureLine(enabled: nil, hasStartedSpend: false, usedFormatted: nil, limitFormatted: nil).text == nil)
    }

    @Test func enabledWithStartedSpendShowsAmounts() {
        let text = ExtraExpenditureLine.text(enabled: true, hasStartedSpend: true, usedFormatted: "13.59 USD", limitFormatted: "50.00 USD")
        #expect(text == "\(Self.title): \(Self.enabled) (13.59 USD / 50.00 USD)")
        #expect(text?.hasSuffix("(13.59 USD / 50.00 USD)") == true)
    }

    @Test func enabledBeforeSpendStartsHasNoParenthetical() {
        let text = ExtraExpenditureLine.text(enabled: true, hasStartedSpend: false, usedFormatted: "0.00 USD", limitFormatted: "50.00 USD")
        #expect(text == "\(Self.title): \(Self.enabled)")
        #expect(text?.contains("(") == false)
    }

    @Test func missingAmountsSuppressTheParenthetical() {
        #expect(ExtraExpenditureLine.text(enabled: true, hasStartedSpend: true, usedFormatted: nil, limitFormatted: "50.00 USD") == "\(Self.title): \(Self.enabled)")
        #expect(ExtraExpenditureLine.text(enabled: true, hasStartedSpend: true, usedFormatted: "13.59 USD", limitFormatted: nil) == "\(Self.title): \(Self.enabled)")
    }

    @Test func disabledShowsDisabled() {
        #expect(ExtraExpenditureLine.text(enabled: false, hasStartedSpend: false, usedFormatted: nil, limitFormatted: nil) == "\(Self.title): \(Self.disabled)")
    }

    // MARK: - ResetCaption

    @Test func unstartedWindowIsExactlyOneWindowAway() {
        let now = Date(timeIntervalSince1970: 1_756_720_000)
        let fiveHours: TimeInterval = 5 * 3600
        let sevenDays: TimeInterval = 7 * 24 * 3600

        #expect(ResetCaption.isUnstartedWindow(now.addingTimeInterval(fiveHours), now: now))
        #expect(ResetCaption.isUnstartedWindow(now.addingTimeInterval(sevenDays), now: now))
        #expect(ResetCaption.isUnstartedWindow(now.addingTimeInterval(fiveHours + 30), now: now))
        #expect(ResetCaption.isUnstartedWindow(now.addingTimeInterval(sevenDays - 45), now: now))
    }

    @Test func startedWindowIsNotFlaggedAsUnstarted() {
        let now = Date(timeIntervalSince1970: 1_756_720_000)
        #expect(!ResetCaption.isUnstartedWindow(now.addingTimeInterval(3 * 24 * 3600), now: now))
        #expect(!ResetCaption.isUnstartedWindow(now.addingTimeInterval(5 * 3600 + 120), now: now))
        #expect(!ResetCaption.isUnstartedWindow(now.addingTimeInterval(4 * 3600), now: now))
        #expect(!ResetCaption.isUnstartedWindow(now, now: now))
    }
}
