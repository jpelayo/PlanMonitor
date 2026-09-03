import Foundation

/// Estimates the current month's final spend.
///
/// This is a projection, not a forecast: it assumes recent behaviour continues, and
/// nothing here can know about a batch job that starts tomorrow. It is deliberately
/// conservative in what it will guess at, because a confidently wrong number on a
/// billing figure is worse than no number.
///
/// Three daily rates are available, trading responsiveness against stability:
///
/// | Rate | Reacts to change | Distorted by |
/// |---|---|---|
/// | last 24 hours | fastest | one unusual day |
/// | this week | medium | start-of-week noise |
/// | this month | slowest | behaviour that has since changed |
///
/// They are blended rather than picked. The weekly rate leads because it absorbs
/// weekday/weekend variation, which is the dominant pattern in API usage; the 24-hour
/// rate pulls the estimate toward a recent change in behaviour; the month rate anchors
/// it. Elapsed time is measured in fractional days, so a partial first day does not
/// inflate the rate.
nonisolated enum SpendProjection {
    /// Below this, too little of the window has elapsed for any rate to mean anything.
    static let minimumElapsedDays = 0.25
    /// Days of the current week after which the weekly rate is trusted in full.
    static let weeklyConfidenceDays = 3.0

    static func project(
        spentThisMonth: Decimal?,
        spentThisWeek: Decimal?,
        spentLast24Hours: Decimal?,
        now: Date
    ) -> Decimal? {
        guard let spentThisMonth else { return nil }

        let calendar = ResetWindowCalculator.utcCalendar
        guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }

        let elapsedMonthDays = now.timeIntervalSince(month.start) / 86_400
        let totalMonthDays = month.end.timeIntervalSince(month.start) / 86_400
        let remainingDays = totalMonthDays - elapsedMonthDays

        // Too early in the month to extrapolate from, and nothing left to extrapolate
        // into: in both cases the honest answer is the actual figure or none at all.
        guard elapsedMonthDays >= minimumElapsedDays else { return nil }
        guard remainingDays > 0 else { return spentThisMonth }

        var rates: [(rate: Double, weight: Double)] = []

        let monthRate = double(spentThisMonth) / elapsedMonthDays
        rates.append((monthRate, 0.2))

        if let spentThisWeek,
           let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            let elapsedWeekDays = now.timeIntervalSince(week.start) / 86_400
            if elapsedWeekDays >= minimumElapsedDays {
                // Confidence in the weekly rate grows with the days behind it. On a
                // Tuesday morning "this week" is one day, and a single heavy Monday
                // would otherwise dominate the whole projection at full weight.
                let confidence = min(1, elapsedWeekDays / weeklyConfidenceDays)
                rates.append((double(spentThisWeek) / elapsedWeekDays, 0.5 * confidence))
            }
        }
        if let spentLast24Hours {
            rates.append((double(spentLast24Hours), 0.3))
        }

        let totalWeight = rates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let blended = rates.reduce(0.0) { $0 + $1.rate * $1.weight } / totalWeight

        let projected = double(spentThisMonth) + blended * remainingDays
        // Spend cannot go backwards, so the projection can never fall below actual.
        return max(spentThisMonth, Decimal(projected))
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
