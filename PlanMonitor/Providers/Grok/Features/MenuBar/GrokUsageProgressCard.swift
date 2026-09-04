import SwiftUI

struct GrokUsageProgressCard: View {
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    var showResetMoment = false
    /// Number of segment hints to draw, for a window whose quota maps onto days (7 for a week).
    /// `nil` draws the plain bar.
    var segments: Int?
    /// Length of the window this card covers (7 days for the weekly pool). With `resetsAt` it
    /// gives the elapsed fraction, drawn as the pace marker. `nil` draws no marker.
    var windowDuration: TimeInterval?

    private var barFraction: Double {
        min(max(usedPercent / 100, 0), 1)
    }

    private var paceFraction: Double? {
        UsageWindowKind.elapsedFraction(resetsAt: resetsAt, duration: windowDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(percentText)
                    .font(.subheadline)
                    .foregroundStyle(colorForUtilization(usedPercent))
            }
            if let segments {
                SegmentedUsageBar(
                    fraction: barFraction,
                    color: colorForUtilization(usedPercent),
                    segments: segments,
                    marker: paceFraction
                )
            } else {
                UsageBar(fraction: barFraction, color: colorForUtilization(usedPercent))
            }
            if let resetsAt {
                HStack {
                    Text(verbatim: "\(String(localized: "Resets")) \(formattedReset(resetsAt))")
                    if showResetMoment {
                        Spacer()
                        Text(formattedResetMoment(resetsAt))
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

    private var percentText: String {
        "\(Int(usedPercent))% \(String(localized: "used"))"
    }

    private func formattedReset(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 {
            return String(localized: "soon")
        }
        return ResetCountdown.format(interval: remaining)
    }

    private func formattedResetMoment(_ date: Date) -> String {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = .current
        weekdayFormatter.dateFormat = "EEEE"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.dateFormat = "H:mm"
        return "\(weekdayFormatter.string(from: date).lowercased()) \(timeFormatter.string(from: date))"
    }
}

func colorForUtilization(_ percent: Double) -> Color {
    switch percent {
    case ..<65: .green
    case 65..<90: Color(red: 0.82, green: 0.42, blue: 0.04)
    default: .red
    }
}
