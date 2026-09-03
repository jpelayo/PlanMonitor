import Foundation
import Testing
@testable import PlanTracker

private func utc(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: string)!
}

private func dbl(_ d: Decimal?) -> Double {
    NSDecimalNumber(decimal: d ?? 0).doubleValue
}

@Suite("Monthly spend projection")
struct SpendProjectionTests {

    /// Steady $10/day through 10 days of a 31-day month should land near $310.
    @Test("A steady rate projects to the month total")
    func steadyRate() {
        let projected = SpendProjection.project(
            spentThisMonth: 100,          // 10 days elapsed, $10/day
            spentThisWeek: 10,            // Tuesday: one day into the week
            spentLast24Hours: 10,
            now: utc("2026-08-11 00:00:00")
        )
        #expect(abs(dbl(projected) - 310) < 15)
    }

    /// The projection is an extrapolation forward; it can never dip below what has
    /// already been spent, whatever the recent rate suggests.
    @Test("Projection never falls below actual month-to-date")
    func neverBelowActual() {
        let projected = SpendProjection.project(
            spentThisMonth: 500,
            spentThisWeek: 0,
            spentLast24Hours: 0,
            now: utc("2026-08-28 12:00:00")
        )
        #expect((projected ?? 0) >= 500)
    }

    /// A quiet start followed by heavy recent use should pull the estimate up, because
    /// the 24-hour rate carries real weight.
    @Test("Recent acceleration raises the estimate above the flat month rate")
    func recentAccelerationCountsMore() {
        let now = utc("2026-08-11 00:00:00")
        let flat = SpendProjection.project(spentThisMonth: 100, spentThisWeek: 10,
                                           spentLast24Hours: 10, now: now)
        let accelerating = SpendProjection.project(spentThisMonth: 100, spentThisWeek: 40,
                                                   spentLast24Hours: 40, now: now)
        #expect(dbl(accelerating) > dbl(flat))
    }

    /// Hours into a month, any rate is noise. Better to show nothing than a wild guess
    /// on a billing figure.
    @Test("Too early in the month yields no estimate")
    func refusesTooEarly() {
        let projected = SpendProjection.project(
            spentThisMonth: Decimal(string: "0.5")!,
            spentThisWeek: Decimal(string: "0.5")!,
            spentLast24Hours: Decimal(string: "0.5")!,
            now: utc("2026-08-01 02:00:00")     // 2 hours in
        )
        #expect(projected == nil)
    }

    @Test("On the last day the projection converges on actual")
    func lastDayConverges() {
        let projected = SpendProjection.project(
            spentThisMonth: 200, spentThisWeek: 40, spentLast24Hours: 8,
            now: utc("2026-08-31 23:00:00")
        )
        #expect(abs(dbl(projected) - 200) < 5)
    }

    @Test("Without month-to-date there is nothing to project from")
    func nilWithoutMonthSpend() {
        #expect(SpendProjection.project(spentThisMonth: nil, spentThisWeek: 10,
                                        spentLast24Hours: 2,
                                        now: utc("2026-08-15 00:00:00")) == nil)
    }

    /// Weekly and 24-hour figures are optional; the month rate alone still works.
    @Test("Falls back to the month rate when finer windows are missing")
    func monthRateAlone() {
        let projected = SpendProjection.project(
            spentThisMonth: 150, spentThisWeek: nil, spentLast24Hours: nil,
            now: utc("2026-08-16 00:00:00")     // 15 of 31 days, $10/day
        )
        #expect(abs(dbl(projected) - 310) < 1)
    }

    /// A month that has barely started for the week (Monday morning) must not let a
    /// near-zero weekly elapsed time explode the rate.
    @Test("A just-started week does not divide by near-zero")
    func weekStartDoesNotExplode() {
        // 2026-08-31 is a Monday; 01:00 UTC is one hour into the week.
        let projected = SpendProjection.project(
            spentThisMonth: 200, spentThisWeek: 5, spentLast24Hours: 7,
            now: utc("2026-08-31 01:00:00")
        )
        #expect(dbl(projected) < 400, "weekly rate leaked an absurd extrapolation")
    }
}


@Suite("Weekly rate confidence")
struct WeeklyConfidenceTests {

    /// Early in a week the weekly rate is discounted, so an unusual Monday cannot
    /// dominate. The same figures later in the week carry more weight.
    @Test("An unusual Monday moves the estimate less than the same rate mid-week")
    func earlyWeekIsDiscounted() {
        // Tuesday, one day in: $40 spent this week reads as $40/day but is discounted.
        let tuesday = SpendProjection.project(
            spentThisMonth: 100, spentThisWeek: 40, spentLast24Hours: 10,
            now: utc("2026-08-11 00:00:00"))
        // Thursday, three days in: the same $40/day rate, now trusted in full.
        let thursday = SpendProjection.project(
            spentThisMonth: 100, spentThisWeek: 120, spentLast24Hours: 10,
            now: utc("2026-08-13 00:00:00"))
        #expect(dbl(thursday) > dbl(tuesday))
    }
}
