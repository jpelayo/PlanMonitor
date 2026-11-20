import SwiftUI

/// One gauge on two lines, for the grouped dropdown: title, used % and short reset over a
/// full-width bar.
/// Provider-neutral — each provider passes its own used fraction and its own severity colour,
/// so no provider's counters are ever read with another's model. Dropdown gauges always show
/// *used*, and so does this.
struct CompactGaugeRow: View {
    let title: String
    /// Used share, 0…1. Values outside are clamped, so it never prints above 100%.
    let fraction: Double
    let color: Color
    var resetsAt: Date? = nil
    /// Daily segment hints, exactly as the provider's dropdown draws this bar. `nil` is the plain bar.
    var segments: Int? = nil
    /// The white pace marker, 0…1 (`UsageWindowKind.elapsedFraction`), as the dropdown passes it.
    var marker: Double? = nil
    var dimmed = false

    /// Fixed right-aligned columns, so the figures line up across every provider's section. The
    /// title takes the rest of line 1 (~180pt of the 288pt row): "Límite adicional de 5 horas"
    /// fits whole, unshrunk.
    static let percentWidth: CGFloat = 34
    static let resetWidth: CGFloat = 58
    /// The dropdowns' bar height, so the notches and the marker read the same.
    static let barHeight: CGFloat = 6

    var body: some View {
        let clamped = Self.clamped(fraction)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: Self.percentText(clamped))
                    .font(.caption.monospacedDigit())
                    .frame(width: Self.percentWidth, alignment: .trailing)
                Text(verbatim: Self.resetText(resetsAt) ?? "")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.resetWidth, alignment: .trailing)
            }
            // The whole row width, as wide as the dropdowns' bars.
            bar(clamped)
        }
        // With the sections' 4pt spacing, 8pt between rows.
        .padding(.top, 4)
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Self.percentText(clamped))
    }

    /// The same bar components the dropdowns use — `SegmentedUsageBar` (notches, white marker)
    /// or the plain `UsageBar` — never a re-drawn copy.
    @ViewBuilder
    private func bar(_ clamped: Double) -> some View {
        if let segments {
            SegmentedUsageBar(fraction: clamped, color: color, segments: segments, height: Self.barHeight, marker: marker)
        } else {
            UsageBar(fraction: clamped, color: color, height: Self.barHeight)
        }
    }

    nonisolated static func clamped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// Integer interpolation, never the locale, and truncated like every dropdown's "N% used".
    nonisolated static func percentText(_ clamped: Double) -> String {
        // The epsilon undoes the round trip through a fraction (29 / 100 * 100 = 28.999…), so a
        // whole percent the dropdown prints as 29 is 29 here too.
        "\(Int(clamped * 100 + 1e-9))%"
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
