import SwiftUI

/// One Claude-API gauge, laid out the same way for every gauge (user decision, 2026-10-14):
///
///     Title                                   used / available
///     [=====                                                 ]
///     90% remaining                           remaining amount
///     Resets in 2 weeks                                  1 Nov
///
/// A slot the console does not report shows "—" rather than disappearing, so every gauge keeps
/// the same four lines. Anything else about a figure belongs in the section below the gauges.
struct ClaudePlatformBudgetGauge: View {
    let title: String
    /// Used, never remaining — the house rule for every dropdown gauge. May exceed 1 on overspend.
    /// `nil` when there is no ceiling to measure against: the bar stays empty and the figures are
    /// neutral, because no severity applies.
    let fraction: Double?
    let usedText: String?
    let availableText: String?
    let remainingText: String?
    let resetsAt: Date?

    private static let missing = "—"

    private var severity: ClaudePlatformSeverity { ClaudePlatformSeverity(fraction) }
    private var clamped: Double { min(max(fraction ?? 0, 0), 1) }
    private var valueColor: Color { fraction == nil ? .secondary : severity.color }

    private var usedOfAvailable: String {
        "\(usedText ?? Self.missing) / \(availableText ?? Self.missing)"
    }

    /// Truncated, like every figure in the app, and never below zero.
    private var percentRemaining: String {
        guard let fraction else { return Self.missing }
        let percent = "\(Int(max(0, 1 - fraction) * 100))%"
        return String(localized: "\(percent) remaining")
    }

    private var resetCountdown: String {
        guard let resetsAt else { return Self.missing }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return String(localized: "Resets \(formatter.localizedString(for: resetsAt, relativeTo: Date()))")
    }

    private var resetDay: String {
        resetsAt?.formatted(.dateTime.day().month(.abbreviated)) ?? Self.missing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(usedOfAvailable)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(valueColor)
            }
            Gauge(value: clamped) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(severity.color)
                .frame(height: 6)
            line(percentRemaining, remainingText ?? Self.missing)
            line(resetCountdown, resetDay)
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ leading: String, _ trailing: String) -> some View {
        HStack(spacing: 6) {
            Text(leading)
            Spacer(minLength: 8)
            Text(trailing)
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
