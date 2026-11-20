import Foundation

/// OpenRouter in the grouped dropdown: one Balances row, never a gauge. Connected, it is what
/// is left of the account credit, written with OpenRouter's own currency style exactly as its
/// dropdown writes it. Not connected, or the key refused, it is the name and the button that
/// fixes it.
enum OpenRouterGroupedBalance {
    static func lines(
        snapshot: OpenRouterSnapshot,
        connectionState: ConnectionState,
        style: CurrencyStyle
    ) -> [BalanceLine] {
        let name = ProviderID.openrouter.displayName
        switch connectionState {
        case .connected:
            // No figure yet is no row, never 0.
            guard let credit = snapshot.accountCredit else { return [] }
            let amount = Money.format(credit.remaining, style: style)
            return [
                BalanceLine(
                    id: "openrouter.credit",
                    provider: name,
                    kind: String(localized: "Credit"),
                    amount: credit.isNegative ? String(localized: "\(amount) overdrawn") : amount,
                    critical: credit.severity == .critical
                )
            ]
        case .invalidKey:
            // A refused key shows no figure anywhere.
            return [
                BalanceLine(
                    id: "openrouter.action",
                    provider: name,
                    action: BalanceAction(title: String(localized: "Replace key"), window: .connectOpenRouter)
                )
            ]
        case .disconnected:
            return [
                BalanceLine(
                    id: "openrouter.action",
                    provider: name,
                    action: BalanceAction(title: String(localized: "Connect"), window: .connectOpenRouter)
                )
            ]
        case .validating:
            return []
        }
    }
}
