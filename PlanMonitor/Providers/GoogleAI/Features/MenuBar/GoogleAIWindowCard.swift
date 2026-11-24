import SwiftUI

/// One agy bucket: title and used %, the bar, and the reset. `OpenCodeWindowCard`'s layout, copied
/// rather than shared (one module is one namespace). The weekly bar is segmented one per day with
/// the pace marker; the 5-hour bar is plain. A window with nothing used shows no reset — agy then
/// reports "now + window", which would move with every poll.
struct GoogleAIWindowCard: View {
    let bucket: GoogleAIBucket

    private var color: Color { GoogleAISeverity(bucket.used).color }

    private var title: String {
        switch bucket.kind {
        case .fiveHour: String(localized: "5-hour limit")
        case .weekly: String(localized: "Weekly limit")
        case .other: bucket.name
        }
    }

    private var percentText: String {
        "\(Int(bucket.used * 100 + 1e-9))% \(String(localized: "used"))"
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
            if bucket.kind == .weekly {
                SegmentedUsageBar(fraction: bucket.used, color: color, segments: 7, marker: bucket.paceFraction())
            } else {
                UsageBar(fraction: bucket.used, color: color)
            }
            if let resetsAt = bucket.shownReset {
                HStack {
                    Text(verbatim: "\(String(localized: "Resets")) \(formattedReset(resetsAt))")
                    if bucket.kind == .weekly {
                        Spacer()
                        Text(ResetCaption.formattedMoment(resetsAt))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bucket.group), \(title)")
        .accessibilityValue(percentText)
    }

    private func formattedReset(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return String(localized: "soon") }
        return ResetCountdown.format(interval: remaining)
    }
}
