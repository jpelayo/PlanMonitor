import Foundation
import Testing
@testable import PlanTracker

struct MenuBarUsageRingTests {
    /// The ring's twelve dashes, as a fraction — the only values `fill` may return.
    private let step = 1.0 / 12.0

    @Test func offLeavesTheRingWhole() {
        #expect(MenuBarUsageRing.fill(source: .off, sense: .remaining, fiveHour: 42, week: 67.5) == nil)
        #expect(MenuBarUsageRing.fill(source: .off, sense: .used, fiveHour: 42, week: 67.5) == nil)
    }

    @Test func noDataLeavesTheRingWhole() {
        #expect(MenuBarUsageRing.fill(source: .week, sense: .remaining, fiveHour: nil, week: nil) == nil)
        #expect(MenuBarUsageRing.fill(source: .fiveHour, sense: .used, fiveHour: nil, week: nil) == nil)
    }

    @Test func fiveHourFallsBackToWeekly() {
        let fallback = MenuBarUsageRing.fill(source: .fiveHour, sense: .used, fiveHour: nil, week: 50)
        let direct = MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: nil, week: 50)
        #expect(fallback == direct)
        #expect(fallback == 6 * step)
    }

    @Test func weeklyFallsBackToFiveHour() {
        #expect(MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: 25, week: nil) == 3 * step)
    }

    @Test func eachSourcePicksItsOwnWindow() {
        #expect(MenuBarUsageRing.fill(source: .fiveHour, sense: .used, fiveHour: 25, week: 75) == 3 * step)
        #expect(MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: 25, week: 75) == 9 * step)
    }

    /// Inputs are used percentages on 0–100; the symbol wants 0–1.
    @Test func usedPercentageIsConvertedToAFraction() {
        #expect(MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: nil, week: 100) == 1)
        #expect(MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: nil, week: 0) == 0)
    }

    @Test func remainingIsTheComplementOfUsed() {
        let used = MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: nil, week: 25)
        let remaining = MenuBarUsageRing.fill(source: .week, sense: .remaining, fiveHour: nil, week: 25)
        #expect(used == 3 * step)
        #expect(remaining == 9 * step)
    }

    /// An untouched quota under `remaining` is a full ring — the same picture as `off`, which is
    /// what makes enabling the gauge a gentle change rather than a jolt.
    @Test func unusedRemainingRingIsFull() {
        #expect(MenuBarUsageRing.fill(source: .week, sense: .remaining, fiveHour: nil, week: 0) == 1)
    }

    @Test func outOfRangeInputIsClamped() {
        #expect(MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: nil, week: 140) == 1)
        #expect(MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: nil, week: -20) == 0)
        #expect(MenuBarUsageRing.fill(source: .week, sense: .remaining, fiveHour: nil, week: 140) == 0)
    }

    /// The guard on change suppression: values inside one dash must produce one image, or the
    /// status item re-renders on every poll for nothing.
    @Test func valuesWithinOneDashQuantiseTogether() {
        let a = MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: nil, week: 42)
        let b = MenuBarUsageRing.fill(source: .week, sense: .used, fiveHour: nil, week: 44)
        #expect(a == b)
        #expect(a == 5 * step)
    }

    @Test func everyResultLandsOnADash() {
        for percent in stride(from: 0.0, through: 100.0, by: 0.5) {
            for sense in [MenuBarRingSense.remaining, .used] {
                let value = MenuBarUsageRing.fill(source: .week, sense: sense, fiveHour: nil, week: percent)
                guard let value else { Issue.record("no fill for \(percent)"); continue }
                let dashes = value * Double(MenuBarUsageRing.steps)
                #expect(abs(dashes - dashes.rounded()) < 1e-9)
                #expect(value >= 0 && value <= 1)
            }
        }
    }
}
