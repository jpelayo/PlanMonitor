import AppKit
import SwiftUI

/// The grouped item's dropdown: every enabled provider's compact section, the money providers'
/// balances, and the shared footer. 320pt like every dropdown, 33%…75% of the screen tall. The
/// sections scroll only past that ceiling; the balances and the footer never move.
struct GroupedMenuBarView: View {
    let entries: [GroupedMenuEntry]
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences

    /// The whole dropdown is between a third and three quarters of the screen's height (user
    /// rule, 2026-11-23): the sections take what the header, balances and footer leave, so every
    /// gauge shows without scrolling unless that ceiling is reached.
    private static let maxScreenShare: CGFloat = 0.75
    private static let minScreenShare: CGFloat = 0.33
    @State private var bodyHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 0
    /// Read once per open: the view is rebuilt every time the popover is shown.
    @State private var screenHeight: CGFloat = GroupedMenuBarView.currentScreenHeight()

    /// The screen the user just clicked on (the item's), else the main one.
    private static func currentScreenHeight() -> CGFloat {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return screen?.frame.height ?? 900
    }

    /// The sections' height: their natural height, clamped so the whole dropdown stays within
    /// 33%…75% of the screen. Below the floor the extra space is left empty under the sections.
    private var sectionsHeight: CGFloat {
        let ceiling = max(screenHeight * Self.maxScreenShare - chromeHeight, 120)
        let floor = min(max(screenHeight * Self.minScreenShare - chromeHeight, 1), ceiling)
        return min(max(bodyHeight, floor), ceiling)
    }

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
                .measuresGroupedChrome()

            if !sections.isEmpty {
                Divider()
                    .measuresGroupedChrome()

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
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: GroupedBodyHeightKey.self, value: proxy.size.height)
                        }
                    )
                }
                .frame(height: sectionsHeight, alignment: .top)
                .onPreferenceChange(GroupedBodyHeightKey.self) { bodyHeight = $0 }
            }

            if !balances.isEmpty {
                Divider()
                    .measuresGroupedChrome()
                balancesBlock(balances)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .measuresGroupedChrome()
            }

            Divider()
                .measuresGroupedChrome()

            footer(shown)
                .measuresGroupedChrome()
        }
        .frame(width: 320)
        .padding(.bottom, 10)
        // The bottom inset belongs to the chrome too.
        .onPreferenceChange(GroupedChromeHeightKey.self) { chromeHeight = $0 + 10 }
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

/// Everything but the sections — header, balances, footer, dividers — summed, so the sections
/// get the rest of the screen share.
private struct GroupedChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private extension View {
    func measuresGroupedChrome() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: GroupedChromeHeightKey.self, value: proxy.size.height)
            }
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
