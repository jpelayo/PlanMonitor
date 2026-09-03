import Foundation

/// Time until a limit resets, at the resolution the number deserves:
/// - a day and a half or more → days in quarters: "6 ½ days", "2 ¼ days", "3 days";
/// - under that → hours and minutes: "31h 5m", "45m".
/// Empty when the moment has passed, so captions can hide themselves.
nonisolated enum ResetCountdown {
    static func format(until date: Date, now: Date = Date()) -> String {
        format(interval: date.timeIntervalSince(now))
    }

    static func format(interval: TimeInterval) -> String {
        guard interval > 0 else { return "" }

        let day: TimeInterval = 86_400
        if interval >= 1.5 * day {
            let quarters = Int((interval / day * 4).rounded())
            let whole = quarters / 4
            let fraction: String
            switch quarters % 4 {
            case 1: fraction = " ¼"
            case 2: fraction = " ½"
            case 3: fraction = " ¾"
            default: fraction = ""
            }
            return String(localized: "\(whole)\(fraction) days")
        }

        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        }
        return String(localized: "\(minutes)m")
    }
}
