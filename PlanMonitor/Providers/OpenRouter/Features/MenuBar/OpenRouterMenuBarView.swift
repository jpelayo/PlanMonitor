import AppKit
import SwiftUI

struct OpenRouterMenuBarView: View {
    @Bindable var viewModel: OpenRouterBudgetViewModel
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences
    @Environment(\.openURL) private var openURL

    /// Body height ceiling. Beyond this the list scrolls rather than growing a popover
    /// taller than the screen.
    private let maxBodyHeight: CGFloat = 420
    @State private var bodyHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // The balance is the reason the app exists, so it stays put. Only the
            // lists below it scroll — those grow without bound on a busy account,
            // and scrolling them must never push the headline figure out of view.
            if viewModel.connectionState.showsBudgets {
                pinnedCredit
                    .padding(.horizontal, 16)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if viewModel.connectionState.showsBudgets {
                        scrollingSections
                    } else {
                        disconnectedContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BodyHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .frame(height: min(max(bodyHeight, 1), maxBodyHeight))
            .onPreferenceChange(BodyHeightKey.self) { bodyHeight = $0 }

            Divider()

            footer
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "PlanMonitor for OpenRouter")).font(.headline)
            if let identity = viewModel.connectionState.identity {
                HStack(spacing: 4) {
                    Text(identity.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if viewModel.isDemoMode {
                        Text(verbatim: "• \(String(localized: "Demo"))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                SessionTimeLine(text: viewModel.dailySessionFormatted)
            }
        }
    }

    // MARK: - Connected

    /// Pinned above the scroll area.
    @ViewBuilder
    private var pinnedCredit: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .invalidKey(let reason) = viewModel.connectionState {
                banner(reason, systemImage: "exclamationmark.triangle", tint: .red)
            }
            creditSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Everything that can grow with the size of the account.
    @ViewBuilder
    private var scrollingSections: some View {
        recentModelsSection
        keySection
        guardrailSection
    }

    /// No gauge here on purpose. `total_credits` is lifetime purchases, not a cap, so
    /// a percentage of it carries no risk signal — only the floor at zero does. The
    /// balance is the headline; the breakdown collapses because seven rows of context
    /// would otherwise bury it.
    @ViewBuilder
    private var creditSection: some View {
        if let credit = viewModel.snapshot.accountCredit {
            Divider()
            sectionTitle("Credit")
            VStack(alignment: .leading, spacing: 3) {
                Text(credit.isNegative
                     ? String(localized: "\(Money.format(credit.remaining)) overdrawn")
                     : String(localized: "\(Money.format(credit.remaining)) remaining"))
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(credit.isNegative ? Color.red : .primary)
                if credit.isNegative {
                    Text("Requests are blocked until you top up.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                spendBreakdown
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var spendBreakdown: some View {
        let rows = spendRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.spendBreakdownExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(viewModel.spendBreakdownExpanded ? 90 : 0))
                        Text("Spending")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Spending breakdown"))
                .accessibilityHint(viewModel.spendBreakdownExpanded
                    ? String(localized: "Collapse")
                    : String(localized: "Expand"))

                if viewModel.spendBreakdownExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(rows, id: \.label) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(row.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text(row.value)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(row.emphasised ? .primary : .secondary)
                            }
                        }
                    }
                    .padding(.leading, 14)
                }
            }
        }
    }

    private struct SpendRow {
        let label: String
        let value: String
        var emphasised = false
    }

    /// Shortest window first, ending with the estimate — so the eye travels from
    /// "what just happened" to "where this month lands".
    private var spendRows: [SpendRow] {
        let snapshot = viewModel.snapshot
        var rows: [SpendRow] = []
        func add(_ label: String, _ amount: Decimal?, emphasised: Bool = false) {
            guard let amount else { return }
            rows.append(SpendRow(label: label, value: Money.format(amount), emphasised: emphasised))
        }
        add(String(localized: "Last 15 minutes"), snapshot.spentLast15Minutes)
        add(String(localized: "Last hour"), snapshot.spentLastHour)
        add(String(localized: "Last 24 hours"), snapshot.spentLast24Hours)
        add(String(localized: "Today"), snapshot.spentToday)
        add(String(localized: "This month"), snapshot.spentThisMonth)
        add(String(localized: "Last 30 days"), snapshot.spentLast30Days)
        add(String(localized: "Projected this month"), snapshot.projectedThisMonth, emphasised: true)
        return rows
    }

    /// Opt-in section: which models actually ran recently, and what they cost.
    /// Hidden by default because it only means something on an active account.
    @ViewBuilder
    private var recentModelsSection: some View {
        if viewModel.showRecentModels {
            Divider()
            sectionTitle("Recent models")
            if viewModel.snapshot.recentModels.isEmpty {
                Text(String(localized: "No models called in the last \(viewModel.recentModelsWindow.displayName)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(viewModel.snapshot.recentModels) { model in
                    modelRow(model)
                }
            }
        }
    }

    /// One line per model: name, how long since it was last called, and what it cost
    /// inside the observed window. The name gets whatever width is left and truncates
    /// in the middle, so the two figures stay aligned at a fixed right edge.
    private func modelRow(_ model: ModelUsage) -> some View {
        HStack(spacing: 8) {
            Text(model.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            // Localised as a whole phrase: English trails with "ago", Spanish leads
            // with "hace", so a bare suffix would not work in both.
            Text(String(localized: "\(ElapsedFormatter.string(since: model.lastCalledAt)) ago"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Text(Money.format(model.spend))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.model)
        .accessibilityValue(String(localized: "\(Money.format(model.spend)), last used \(ElapsedFormatter.string(since: model.lastCalledAt)) ago"))
    }

    @ViewBuilder
    private var keySection: some View {
        let budgets = viewModel.snapshot.keyBudgets.filter { viewModel.showDisabledKeys || !$0.disabled }
        let uncapped = viewModel.snapshot.uncappedKeys.filter { viewModel.showDisabledKeys || !$0.disabled }

        if !budgets.isEmpty || !uncapped.isEmpty {
            Divider()
            sectionTitle("API key limits")
            ForEach(budgets) { budget in
                OpenRouterBudgetGauge(
                    fraction: budget.usedFraction,
                    title: budget.name,
                    detail: keyDetail(budget),
                    valueText: "\(Money.format(budget.spent)) / \(Money.format(budget.limit))",
                    dimmed: budget.disabled
                )
            }
            ForEach(uncapped) { key in
                HStack {
                    Text(key.name).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(String(localized: "\(Money.format(key.spentInWindow)) spent"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .opacity(key.disabled ? 0.55 : 1)
            }
        }
    }

    private func keyDetail(_ budget: KeyBudget) -> String? {
        var parts: [String] = []
        if let reset = ResetFormatter.describe(budget.window) { parts.append(reset) }
        else { parts.append(String(localized: "lifetime cap")) }
        if budget.disabled { parts.append(String(localized: "disabled")) }
        if budget.isApproximate { parts.append(String(localized: "approximate")) }
        return parts.joined(separator: " · ")
    }

    /// Guardrails are an org feature. On a personal account the section is absent —
    /// not an error banner. See build plan §6.5.
    ///
    /// Members are always visible rather than hidden behind a disclosure control. The
    /// per-key breakdown *is* the point — a guardrail budget applies to each assigned
    /// key independently — so hiding it behind a chevron buries the one thing that
    /// makes the numbers readable. Groups are separated by a rule instead.
    @ViewBuilder
    private var guardrailSection: some View {
        let budgets = viewModel.snapshot.guardrailBudgets
        if viewModel.snapshot.guardrailsAvailable && !budgets.isEmpty {
            Divider()
            sectionTitle("Guardrails")
            ForEach(Array(budgets.enumerated()), id: \.element.id) { index, guardrail in
                if index > 0 {
                    Divider().padding(.vertical, 2)
                }
                guardrailGroup(guardrail)
            }
        }
    }

    @ViewBuilder
    private func guardrailGroup(_ guardrail: GuardrailBudget) -> some View {
        if guardrail.members.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(guardrail.name).font(.subheadline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Money.format(guardrail.limit))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(String(localized: "No keys assigned"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else if guardrail.members.count == 1, let member = guardrail.members.first {
            // One key: the guardrail name alone identifies the row.
            OpenRouterBudgetGauge(
                fraction: member.usedFraction,
                title: guardrail.name,
                detail: guardrailDetail(guardrail, member: member),
                valueText: "\(Money.format(member.spent)) / \(Money.format(guardrail.limit))"
            )
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(guardrail.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(String(localized: "\(Money.format(guardrail.limit)) each"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let detail = guardrailDetail(guardrail, member: nil) {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(guardrail.members) { member in
                    OpenRouterBudgetGauge(
                        fraction: member.usedFraction,
                        title: member.keyName,
                        detail: member.supersededByKeyLimit
                            ? String(localized: "key's own limit binds first")
                            : nil,
                        valueText: "\(Money.format(member.spent)) / \(Money.format(member.limit))"
                    )
                    .padding(.leading, 10)
                }
            }
        }
    }

    private func guardrailDetail(_ guardrail: GuardrailBudget, member: GuardrailKeyBudget?) -> String? {
        var parts: [String] = []
        if let reset = ResetFormatter.describe(guardrail.window) { parts.append(reset) }
        if member == nil {
            parts.append(String(localized: "\(guardrail.members.count) keys, each with its own budget"))
        }
        if guardrail.includesBYOK { parts.append(String(localized: "includes BYOK")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Disconnected

    /// Same shape as the other providers' signed-out screens; the management-key
    /// explanation lives in the Connect window, where the key is entered.
    private var disconnectedContent: some View {
        VStack(spacing: 16) {
            SignedOutHeader(
                symbolName: "dollarsign.ring.dashed",
                fallbackSymbol: "ring.dashed",
                title: String(localized: "Connect OpenRouter"),
                subtitle: String(localized: "Track your OpenRouter credit and limits from the menu bar"),
                actionTitle: String(localized: "Connect"),
                action: { WindowRouter.shared.open(.connectOpenRouter) }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    /// Full-width tappable rows with leading labels, following the Claude variant.
    /// Deliberately not `.buttonStyle(.link)` — blue underlined text reads as a web
    /// page, not a menu.
    private var footer: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                statusText(error, tint: .red)
            } else if let degraded = viewModel.degradedMessage {
                statusText(degraded, tint: .orange)
            }
            if let updated = viewModel.lastUpdated {
                statusText(
                    viewModel.isStale
                        ? String(localized: "Stale — last updated \(relative(updated))")
                        : String(localized: "Updated \(relative(updated))"),
                    tint: .secondary
                )
            }

            Divider()

            if viewModel.connectionState.showsBudgets {
                SharedMenuFooter(
                    providers: providers,
                    preferences: preferences,
                    isRefreshing: viewModel.isLoading,
                    nextRefreshAt: viewModel.nextRefreshAt,
                    refreshAction: { await viewModel.refresh() }
                )
            } else {
                SharedMenuFooter(
                    providers: providers,
                    preferences: preferences,
                    isRefreshing: false,
                    nextRefreshAt: nil,
                    refreshAction: nil
                )
            }
        }
    }

    private func statusText(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    private func rowLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }

    private func actionRow<Trailing: View>(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func banner(_ message: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(message).font(.caption)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}


/// Reports the scrollable content's natural height so the popover can size to it.
private struct BodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
