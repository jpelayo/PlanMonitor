import SwiftUI

/// OpenRouter's section of the grouped dropdown: its key-limit and guardrail gauges, one line
/// each, with the same fractions and colours its dropdown draws. Its credit is not a gauge —
/// lifetime purchases are no cap — so it goes to the Balances block instead.
struct OpenRouterGroupedSection: View {
    @Bindable var viewModel: OpenRouterBudgetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch viewModel.connectionState {
            case .connected:
                GroupedSectionHeader(
                    title: ProviderID.openrouter.displayName,
                    staleSince: viewModel.isStale ? viewModel.lastUpdated : nil,
                    isDemo: viewModel.isDemoMode
                )
                rows
            case .invalidKey(let reason):
                // A refused key: no figures, the reason and the way out.
                GroupedSectionHeader(
                    title: ProviderID.openrouter.displayName,
                    actionTitle: String(localized: "Replace key"),
                    action: { WindowRouter.shared.open(.connectOpenRouter) }
                )
                if !reason.isEmpty {
                    GroupedSectionNote(text: reason, tint: .red)
                }
            case .validating:
                GroupedSectionHeader(title: ProviderID.openrouter.displayName)
                ProgressView().controlSize(.small)
            case .disconnected:
                GroupedSectionHeader(
                    title: ProviderID.openrouter.displayName,
                    actionTitle: String(localized: "Connect"),
                    action: { WindowRouter.shared.open(.connectOpenRouter) }
                )
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let snapshot = viewModel.snapshot
        let keys = snapshot.keyBudgets.filter { viewModel.showDisabledKeys || !$0.disabled }
        ForEach(keys) { budget in
            CompactGaugeRow(
                title: budget.name,
                fraction: budget.usedFraction,
                color: BudgetSeverity(budget.usedFraction).color,
                resetsAt: budget.window.nextReset,
                dimmed: budget.disabled
            )
        }
        if snapshot.guardrailsAvailable {
            ForEach(snapshot.guardrailBudgets) { guardrail in
                ForEach(guardrail.members) { member in
                    CompactGaugeRow(
                        // One key: the guardrail's name identifies the row, as in the dropdown.
                        title: guardrail.members.count == 1 ? guardrail.name : member.keyName,
                        fraction: member.usedFraction,
                        color: BudgetSeverity(member.usedFraction).color,
                        resetsAt: guardrail.window.nextReset
                    )
                }
            }
        }
        if let error = viewModel.errorMessage {
            GroupedSectionNote(text: error, tint: .red)
        }
    }
}

/// OpenRouter's line in the Balances block: what is left of the account credit, written with
/// OpenRouter's own currency style, exactly as its dropdown writes it.
enum OpenRouterGroupedBalance {
    static func lines(
        snapshot: OpenRouterSnapshot,
        connectionState: ConnectionState,
        style: CurrencyStyle
    ) -> [BalanceLine] {
        // Connected only: a refused key shows no figures anywhere.
        guard connectionState.isConnected, let credit = snapshot.accountCredit else { return [] }
        let amount = Money.format(credit.remaining, style: style)
        return [
            BalanceLine(
                id: "openrouter.credit",
                provider: ProviderID.openrouter.displayName,
                kind: String(localized: "Credit"),
                amount: credit.isNegative ? String(localized: "\(amount) overdrawn") : amount,
                critical: credit.severity == .critical
            )
        ]
    }
}
