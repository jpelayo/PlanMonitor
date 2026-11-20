import SwiftUI

/// The grouped item's dropdown: every enabled provider's compact section, the money providers'
/// balances, and the shared footer. 320pt like every dropdown. The sections scroll past a
/// ceiling; the balances and the footer never move.
struct GroupedMenuBarView: View {
    let entries: [GroupedMenuEntry]
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences

    /// Six providers with two to four rows each fit under this; more scroll.
    private let maxBodyHeight: CGFloat = 460
    @State private var bodyHeight: CGFloat = 0

    /// In `ProviderID` order — the order the entries are built in — enabled ones only.
    /// Enabled ones only, in the user's order (Settings › Grouped menu) — sections and Balances
    /// rows alike.
    private var enabledEntries: [GroupedMenuEntry] {
        let enabled = entries.filter { providers.isEnabled($0.id) }
        let order = GroupedMenuOrder.sorted(enabled.map(\.id), by: preferences.groupedOrder)
        return order.compactMap { id in enabled.first { $0.id == id } }
    }

    var body: some View {
        let shown = enabledEntries
        let balances = shown.flatMap { $0.balances() }
        // Gauge providers only: OpenRouter and Claude-API have no section, just Balances lines.
        let sections = shown.compactMap { entry in entry.section.map { (id: entry.id, view: $0) } }

        VStack(alignment: .leading, spacing: 0) {
            header(shown)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if !sections.isEmpty {
                Divider()

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            if index > 0 {
                                Divider().padding(.vertical, 8)
                            }
                            section.view()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: GroupedBodyHeightKey.self, value: proxy.size.height)
                        }
                    )
                }
                .frame(height: min(max(bodyHeight, 1), maxBodyHeight))
                .onPreferenceChange(GroupedBodyHeightKey.self) { bodyHeight = $0 }
            }

            if !balances.isEmpty {
                Divider()
                balancesBlock(balances)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            Divider()

            footer(shown)
        }
        .frame(width: 320)
        .padding(.bottom, 10)
        .environment(\.groupedTitleSize, preferences.groupedTitleSize)
        .environment(\.groupedAmountSize, preferences.groupedAmountSize)
    }

    private func header(_ shown: [GroupedMenuEntry]) -> some View {
        HStack {
            Text(verbatim: "PlanMonitor")
                .font(.headline)
            Spacer()
            if shown.contains(where: { $0.isDemo() }) {
                Text(verbatim: "• \(String(localized: "Demo"))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func balancesBlock(_ lines: [BalanceLine]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "Balances"), systemImage: "banknote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(lines) { line in
                // The name follows the title size, the figure the amount size (Settings › Grouped
                // menu). Name, date and figure never truncate; only the kind may shrink.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: line.provider)
                        .font(.system(size: preferences.groupedTitleSize.points, weight: .semibold))
                        .fixedSize()
                        .layoutPriority(1)
                    if !line.kind.isEmpty {
                        Text(line.kind)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 8)
                    if let date = line.date {
                        Text(verbatim: date)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                    if let amount = line.amount {
                        Text(verbatim: amount)
                            .font(.system(size: preferences.groupedAmountSize.points).monospacedDigit())
                            .foregroundStyle(line.critical ? Color.red : .primary)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                    if let action = line.action {
                        Button(action.title) { WindowRouter.shared.open(action.window) }
                            .controlSize(.small)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(_ shown: [GroupedMenuEntry]) -> some View {
        let refreshable = shown.filter { $0.canRefresh() }
        let now = Date()
        return SharedMenuFooter(
            providers: providers,
            preferences: preferences,
            isRefreshing: shown.contains { $0.isRefreshing() },
            nextRefreshAt: shown.compactMap { $0.nextRefreshAt() }.filter { $0 > now }.min(),
            refreshAction: {
                // Each provider's own Refresh, all at once: the same call its dropdown makes,
                // so each restarts its own cycle exactly as it would there.
                let actions = refreshable.map(\.refresh)
                await withTaskGroup(of: Void.self) { group in
                    for action in actions {
                        group.addTask { await action() }
                    }
                }
            },
            refreshEnabled: !refreshable.isEmpty
        )
    }
}

/// The scrolling sections' natural height, so the popover sizes to them up to the ceiling.
private struct GroupedBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
