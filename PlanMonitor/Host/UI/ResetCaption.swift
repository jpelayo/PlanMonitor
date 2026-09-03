import SwiftUI

/// "Resets in 3d 4h" with, for multi-day windows, the absolute moment right-aligned
/// ("sunday 15:00"). Renders nothing when the countdown is empty, which also suppresses the
/// bare "Resets " an already-passed date used to produce. The moment is hidden while a window
/// has not started yet (the reset sits exactly one full window away), because that date is
/// just "now plus the window length" and would move with every poll.
struct ResetCaption: View {
    let countdown: String?
    var moment: Date? = nil

    var body: some View {
        if let countdown, !countdown.isEmpty {
            HStack {
                Text(verbatim: "\(String(localized: "Resets")) \(countdown)")
                if let moment, !Self.isUnstartedWindow(moment) {
                    Spacer()
                    Text(Self.formattedMoment(moment))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    static func isUnstartedWindow(_ resetAt: Date, now: Date = Date()) -> Bool {
        let remaining = resetAt.timeIntervalSince(now)
        let windows: [TimeInterval] = [5 * 3600, 7 * 24 * 3600]
        return windows.contains { abs(remaining - $0) <= 60 }
    }

    static func formattedMoment(_ date: Date) -> String {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = .current
        weekdayFormatter.dateFormat = "EEEE"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.dateFormat = "H:mm"
        return "\(weekdayFormatter.string(from: date).lowercased()) \(timeFormatter.string(from: date))"
    }
}
