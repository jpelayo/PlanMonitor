import SwiftUI

/// One gauge on one line, for the grouped dropdown: title, thin bar, used %, short reset.
/// Provider-neutral — each provider passes its own used fraction and its own severity colour,
/// so no provider's counters are ever read with another's model. Dropdown gauges always show
/// *used*, and so does this.
struct CompactGaugeRow: View {
    let title: String
    /// Used share, 0…1. Values outside are clamped, so it never prints above 100%.
    let fraction: Double
    let color: Color
    var resetsAt: Date? = nil
    var dimmed = false

    /// Fixed columns, so rows line up across every provider's section. The title column fits
    /// "Límite de 5 horas"; longer titles shrink a little before they truncate. What is left of
    /// the 288pt row after the gaps is the bar's, never less than 60pt.
    static let titleWidth: CGFloat = 110
    static let percentWidth: CGFloat = 34
    static let resetWidth: CGFloat = 58

    var body: some View {
        let clamped = Self.clamped(fraction)
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .frame(width: Self.titleWidth, alignment: .leading)
            UsageBar(fraction: clamped, color: color, height: 4)
                .frame(minWidth: 60)
            Text(verbatim: Self.percentText(clamped))
                .font(.caption.monospacedDigit())
                .frame(width: Self.percentWidth, alignment: .trailing)
            Text(verbatim: Self.resetText(resetsAt) ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.resetWidth, alignment: .trailing)
        }
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Self.percentText(clamped))
    }

    nonisolated static func clamped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// Integer interpolation, never the locale: a dot-free whole number and a percent sign.
    nonisolated static func percentText(_ clamped: Double) -> String {
        "\(Int((clamped * 100).rounded()))%"
    }

    /// "42m" under an hour, "2h 05m" under a day, otherwise the weekday and time ("thu 9:00"),
    /// in `ResetCaption.formattedMoment`'s style. Nothing for a missing or past date, or for a
    /// window that has not started (its reset is just "now plus the window" and would move
    /// with every poll).
    static func resetText(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0, !ResetCaption.isUnstartedWindow(date, now: now) else { return nil }
        let totalMinutes = max(1, Int((remaining / 60).rounded(.down)))
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        if remaining < 24 * 3600 {
            return "\(totalMinutes / 60)h \(String(format: "%02d", totalMinutes % 60))m"
        }
        let weekday = DateFormatter()
        weekday.locale = .current
        weekday.dateFormat = "EEE"
        let time = DateFormatter()
        time.locale = .current
        time.dateFormat = "H:mm"
        let day = weekday.string(from: date).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return "\(day) \(time.string(from: date))"
    }
}

/// The first line of every provider's section in the grouped dropdown: name, plan, and — only
/// when something needs attention — a status mark, a stale mark, or the one action that fixes
/// a signed-out or refused state. Operational shows nothing, so the list stays calm.
struct GroupedSectionHeader: View {
    struct Alert {
        let title: String
        let isOutage: Bool
    }

    let title: String
    var detail: String? = nil
    var alert: Alert? = nil
    /// When the figures below were last good, while they are stale.
    var staleSince: Date? = nil
    var isDemo = false
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
            if let detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if isDemo {
                Text(verbatim: "• \(String(localized: "Demo"))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 4)
            if let staleSince {
                let text = String(localized: "Stale — last updated \(Self.relative(staleSince))")
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(text)
                    .accessibilityLabel(text)
            }
            if let alert {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(alert.isOutage ? Color.red : Color.orange)
                    .help(alert.title)
                    .accessibilityLabel(alert.title)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// A one-line message under a section header: an error, a reason, a neutral note.
struct GroupedSectionNote: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(tint)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
