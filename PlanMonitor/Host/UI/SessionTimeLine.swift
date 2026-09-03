import SwiftUI

/// The header row every provider dropdown uses for its session time. The leading text sits in
/// a full-width container so the row keeps its height when there is nothing to show, and the
/// optional trailing accessory (Claude's status pill) stays right-aligned either way.
struct SessionTimeLine<Trailing: View>: View {
    let text: String?
    @ViewBuilder var trailing: () -> Trailing

    init(text: String?, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let text {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
