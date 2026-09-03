import SwiftUI

/// The single gauge used by every row. Claude's OpenRouterMenuBarView repeats twelve inline
/// ProgressViews; this app has more rows than that, so the component is extracted once.
struct OpenRouterBudgetGauge: View {
    enum Style {
        case prominent   // credit headline
        case row         // key and guardrail rows
    }

    let fraction: Double        // may exceed 1.0 on overspend
    let title: String
    let detail: String?
    let valueText: String
    var style: Style = .row
    var dimmed: Bool = false

    private var severity: BudgetSeverity { BudgetSeverity(fraction) }
    private var clamped: Double { min(max(fraction, 0), 1) }
    private var isOverspent: Bool { fraction > 1 }

    var body: some View {
        switch style {
        case .prominent: prominentBody
        case .row: rowBody
        }
    }

    private var prominentBody: some View {
        HStack(spacing: 12) {
            Gauge(value: clamped) {
                EmptyView()
            } currentValueLabel: {
                Text(verbatim: "\(Int((clamped * 100).rounded()))")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(severity.color)
            .scaleEffect(0.85)
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(valueText)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(isOverspent ? Color.red : .primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail.map { "\(valueText), \($0)" } ?? valueText)
    }

    private var rowBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(severity.color)
            }
            Gauge(value: clamped) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(severity.color)
                .frame(height: 6)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail.map { "\(valueText), \($0)" } ?? valueText)
    }
}

/// Renders a reset window as a locale-formatted countdown. All arithmetic is UTC; only
/// the presentation is local.
nonisolated enum ResetFormatter {
    static func describe(_ window: ResetWindow, now: Date = Date()) -> String? {
        guard let interval = window.interval else { return nil }
        guard let next = window.nextReset else { return interval.displayName }
        if next <= now { return String(localized: "\(interval.displayName) · resetting now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: next, relativeTo: now)
        return String(localized: "\(interval.displayName) · resets \(relative)")
    }
}
