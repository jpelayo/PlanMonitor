import Foundation

/// A budget's reset cadence. `nil` interval means a lifetime cap that never resets.
nonisolated enum ResetInterval: String, Codable, Sendable, CaseIterable {
    case daily
    case weekly
    case monthly

    var displayName: String {
        switch self {
        case .daily: String(localized: "daily")
        case .weekly: String(localized: "weekly")
        case .monthly: String(localized: "monthly")
        }
    }
}

nonisolated struct ResetWindow: Codable, Equatable, Sendable {
    var interval: ResetInterval?
    var windowStart: Date?
    var nextReset: Date?

    static let lifetime = ResetWindow(interval: nil, windowStart: nil, nextReset: nil)

    var resets: Bool { interval != nil }
}

/// All OpenRouter usage windows are UTC: day boundaries at 00:00 UTC, weeks starting
/// Monday, months on the 1st. The API returns no reset timestamp, so we derive it.
/// Rendering happens in the user's locale; only the arithmetic is UTC.
nonisolated enum ResetWindowCalculator {
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // ISO-8601 weeks start on Monday, which is what OpenRouter uses.
        calendar.firstWeekday = 2
        return calendar
    }

    static func window(for interval: ResetInterval?, now: Date) -> ResetWindow {
        guard let interval else { return .lifetime }
        let calendar = utcCalendar

        let start: Date?
        switch interval {
        case .daily:
            start = calendar.startOfDay(for: now)
        case .weekly:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .monthly:
            start = calendar.dateInterval(of: .month, for: now)?.start
        }

        guard let windowStart = start else {
            return ResetWindow(interval: interval, windowStart: nil, nextReset: nil)
        }

        let component: Calendar.Component = switch interval {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }
        let next = calendar.date(byAdding: component, value: 1, to: windowStart)

        return ResetWindow(interval: interval, windowStart: windowStart, nextReset: next)
    }
}
