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
    private var enabledEntries: [GroupedMenuEntry] {
        entries.filter { providers.isEnabled($0.id) }
    }

    var body: some View {
        let shown = enabledEntries
        let balances = shown.flatMap { $0.balances() }

        VStack(alignment: .leading, spacing: 0) {
            header(shown)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().padding(.vertical, 8)
                        }
                        entry.section()
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
                HStack(spacing: 6) {
                    Text(verbatim: line.provider)
                        .font(.caption)
                    Text(line.kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: line.amount)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(line.critical ? Color.red : .primary)
                }
                .accessibilityElement(children: .combine)
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
