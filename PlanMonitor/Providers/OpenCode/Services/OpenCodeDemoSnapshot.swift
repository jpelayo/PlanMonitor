import Foundation

/// Deterministic App Review data. The Go windows sit at plausible mid-cycle values; the spend is the
/// Console API docs' own example — $12.50 of a $75.25 custom budget. Resets are placed relative to
/// `now` where the backend's own rules put them (five hours of activity; Monday 00:00 UTC; a month
/// from subscribing), so the countdowns read sensibly whenever the demo runs. `OpenCodeDemoTests`
/// holds every card and row to it.
nonisolated enum OpenCodeDemoSnapshot {
    static func snapshot(now: Date = Date()) -> OpenCodeSnapshot {
        OpenCodeSnapshot(
            go: OpenCodeGoUsage(
                rolling: OpenCodeGoWindow(usedPercent: 38, resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60), isRateLimited: false),
                weekly: OpenCodeGoWindow(usedPercent: 61, resetsAt: nextUTCMonday(after: now), isRateLimited: false),
                monthly: OpenCodeGoWindow(usedPercent: 24, resetsAt: now.addingTimeInterval(18 * 24 * 3600), isRateLimited: false)
            ),
            budgetsReadable: true,
            memberEmail: identityLabel,
            spent: Decimal(string: "12.50", locale: Locale(identifier: "en_US_POSIX")),
            budget: Decimal(string: "75.25", locale: Locale(identifier: "en_US_POSIX")),
            exceeded: false,
            resetsAt: startOfNextUTCMonth(after: now),
            budgetSource: .custom,
            memberCount: 1,
            isWorkspaceTotal: false,
            fetchedAt: now
        )
    }

    static let identityLabel = "demo@example.com"
    static let keyPrefix = "oc_sk_000000000000"

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private static func startOfNextUTCMonth(after date: Date) -> Date? {
        utc.dateInterval(of: .month, for: date)?.end
    }

    private static func nextUTCMonday(after date: Date) -> Date? {
        utc.dateInterval(of: .weekOfYear, for: date)?.end
    }
}
