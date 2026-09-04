import Foundation
import Testing
@testable import PlanTracker

/// The formatting rules here predate the helper — every provider truncated and every provider
/// printed `NN%`. Drift in truncation or clamping would silently change the digits for every
/// existing user, so those cases are asserted explicitly.
struct MenuBarUsageDigitsTests {
    @Test func fiveHourShowsOnlyTheFiveHourWindow() {
        let resolved = MenuBarUsageDigits.resolve(display: .fiveHour, fiveHour: 55, week: 7, showRemainingPercent: false)
        #expect(resolved.text == "55%")
        #expect(resolved.severityUtilization == 55)
    }

    @Test func weekShowsOnlyTheWeeklyWindow() {
        let resolved = MenuBarUsageDigits.resolve(display: .week, fiveHour: 55, week: 7, showRemainingPercent: false)
        #expect(resolved.text == "7%")
        #expect(resolved.severityUtilization == 7)
    }

    @Test func bothJoinsFiveHourFirst() {
        let resolved = MenuBarUsageDigits.resolve(display: .both, fiveHour: 55, week: 7, showRemainingPercent: false)
        #expect(resolved.text == "55%\u{00B7}7%")
    }

    @Test func bothTintsFromTheWorseWindow() {
        let fiveHourWorse = MenuBarUsageDigits.resolve(display: .both, fiveHour: 55, week: 7, showRemainingPercent: false)
        #expect(fiveHourWorse.severityUtilization == 55)

        let weekWorse = MenuBarUsageDigits.resolve(display: .both, fiveHour: 12, week: 91, showRemainingPercent: false)
        #expect(weekWorse.severityUtilization == 91)
    }

    @Test func fiveHourFallsBackToWeek() {
        let resolved = MenuBarUsageDigits.resolve(display: .fiveHour, fiveHour: nil, week: 7, showRemainingPercent: false)
        #expect(resolved.text == "7%")
        #expect(resolved.severityUtilization == 7)
    }

    @Test func weekFallsBackToFiveHour() {
        let resolved = MenuBarUsageDigits.resolve(display: .week, fiveHour: 55, week: nil, showRemainingPercent: false)
        #expect(resolved.text == "55%")
    }

    @Test func bothWithOneWindowShowsThatWindowAlone() {
        let noWeek = MenuBarUsageDigits.resolve(display: .both, fiveHour: 55, week: nil, showRemainingPercent: false)
        #expect(noWeek.text == "55%")

        let noFiveHour = MenuBarUsageDigits.resolve(display: .both, fiveHour: nil, week: 7, showRemainingPercent: false)
        #expect(noFiveHour.text == "7%")
    }

    @Test func noDataYieldsNoText() {
        for display in MenuBarUsageDisplay.allCases {
            let resolved = MenuBarUsageDigits.resolve(display: display, fiveHour: nil, week: nil, showRemainingPercent: false)
            #expect(resolved.text == nil)
            #expect(resolved.severityUtilization == nil)
        }
    }

    @Test func remainingInvertsBothHalvesButNotSeverity() {
        let resolved = MenuBarUsageDigits.resolve(display: .both, fiveHour: 55, week: 7, showRemainingPercent: true)
        #expect(resolved.text == "45%\u{00B7}93%")
        // Severity is always the *used* percentage, whatever the digits display.
        #expect(resolved.severityUtilization == 55)
    }

    @Test func percentagesTruncateRatherThanRound() {
        let resolved = MenuBarUsageDigits.resolve(display: .fiveHour, fiveHour: 6.9, week: nil, showRemainingPercent: false)
        #expect(resolved.text == "6%")
    }

    @Test func remainingClampsAtZeroWhenOverBudget() {
        let resolved = MenuBarUsageDigits.resolve(display: .fiveHour, fiveHour: 120, week: nil, showRemainingPercent: true)
        #expect(resolved.text == "0%")
    }
}
