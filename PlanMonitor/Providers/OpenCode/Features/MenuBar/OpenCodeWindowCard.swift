import SwiftUI

/// One Go window: title and used %, the bar, and the reset. Copied from `GrokUsageProgressCard`
/// and renamed — one module is one namespace — with its colour taken from `OpenCodeSeverity` rather
/// than Grok's file-level `colorForUtilization`, and a window the backend has rate-limited saying
/// so in red instead of a bare `100%`.
struct OpenCodeWindowCard: View {
    enum ResetMoment {
        case none
        /// `monday 0:00` — the weekly window.
        case weekdayAndTime
        /// `22 Nov` — the monthly window.
        case day
    }

    let title: String
    let window: OpenCodeGoWindow
    var resetMoment: ResetMoment = .none
    /// Number of segment hints to draw, for a window whose quota maps onto days (7 for a week).
    /// `nil` draws the plain bar.
    var segments: Int?
    /// Length of the window, which with `resetsAt` gives the pace marker. `nil` draws no marker.
    var windowDuration: TimeInterval?

    private var barFraction: Double {
        min(max(window.effectivePercent / 100, 0), 1)
    }

    private var color: Color {
        OpenCodeSeverity(window.effectivePercent / 100).color
    }

    private var paceFraction: Double? {
        UsageWindowKind.elapsedFraction(resetsAt: window.resetsAt, duration: windowDuration)
    }

    private var percentText: String {
        window.isRateLimited
            ? String(localized: "Limit reached")
            : "\(Int(window.usedPercent))% \(String(localized: "used"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(percentText)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }
            if let segments {
                SegmentedUsageBar(fraction: barFraction, color: color, segments: segments, marker: paceFraction)
            } else {
                UsageBar(fraction: barFraction, color: color)
            }
            if let resetsAt = window.resetsAt {
                HStack {
                    Text(verbatim: "\(String(localized: "Resets")) \(formattedReset(resetsAt))")
                    if let moment = formattedMoment(resetsAt) {
                        Spacer()
                        Text(moment)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(percentText)
    }

    private func formattedReset(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return String(localized: "soon") }
        return ResetCountdown.format(interval: remaining)
    }

    private func formattedMoment(_ date: Date) -> String? {
        switch resetMoment {
        case .none:
            return nil
        case .weekdayAndTime:
            let weekday = DateFormatter()
            weekday.locale = .current
            weekday.dateFormat = "EEEE"
            let time = DateFormatter()
            time.locale = .current
            time.dateFormat = "H:mm"
            return "\(weekday.string(from: date).lowercased()) \(time.string(from: date))"
        case .day:
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}
