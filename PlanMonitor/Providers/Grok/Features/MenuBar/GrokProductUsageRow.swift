import SwiftUI

struct GrokProductUsageRow: View {
    let item: GrokProductUsage

    var body: some View {
        HStack {
            Circle()
                .fill(colorForUtilization(item.utilization * 100))
                .frame(width: 8, height: 8)
            Text(item.displayName)
                .font(.caption)
            Spacer()
            Text(verbatim: "\(Int((item.utilization * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName)
        .accessibilityValue("\(Int((item.utilization * 100).rounded()))%")
    }
}
