import Foundation

/// How far back the recent-models section looks.
///
/// The choice also decides which query feeds it. Up to an hour the minute-granularity
/// window already fetched for the spend breakdown is reused; beyond that the hourly
/// 24-hour query is used instead, because a day at minute granularity would be ~1440
/// buckets per model and could hit the API's row cap.
nonisolated enum RecentModelsWindow: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case threeHours = 180
    case sixHours = 360
    case twelveHours = 720
    case twentyFourHours = 1440

    var id: Int { rawValue }
    var minutes: Int { rawValue }

    /// True when the minute-granularity feed covers this window.
    var usesMinuteGranularity: Bool { rawValue <= 60 }

    var displayName: String {
        switch self {
        case .fifteenMinutes: String(localized: "15 minutes")
        case .thirtyMinutes: String(localized: "30 minutes")
        case .oneHour: String(localized: "1 hour")
        case .threeHours: String(localized: "3 hours")
        case .sixHours: String(localized: "6 hours")
        case .twelveHours: String(localized: "12 hours")
        case .twentyFourHours: String(localized: "24 hours")
        }
    }
}

/// Elapsed time in the `hh:mm` form used by the recent-models rows.
nonisolated enum ElapsedFormatter {
    static func string(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let totalMinutes = Int(seconds / 60)
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}
