import Foundation

/// Claude-API in the grouped dropdown: one or two Balances rows, never a gauge — the credit left
/// (promotional and prepaid, expired promotional tranches already dropped), and what is waiting
/// to be invoiced when the account reports it. Written with Claude-API's own currency style; a
/// missing figure is no row, never 0. Signed out, it is the name and Sign In.
enum ClaudePlatformGroupedBalance {
    static func lines(
        snapshot: ClaudePlatformSnapshot,
        isSignedIn: Bool,
        style: CurrencyStyle,
        now: Date = Date()
    ) -> [BalanceLine] {
        let name = ProviderID.claudeapi.displayName
        guard isSignedIn else {
            return [
                BalanceLine(
                    id: "claudeapi.action",
                    provider: name,
                    action: BalanceAction(title: String(localized: "Sign In"), window: .loginClaudeAPI)
                )
            ]
        }
        let figures = snapshot.figures
        var lines: [BalanceLine] = []
        if let left = figures.creditLeft {
            lines.append(BalanceLine(
                id: "claudeapi.creditLeft",
                provider: name,
                kind: String(localized: "Credit left"),
                date: resetDay(snapshot.promoExpiresAt, now: now),
                amount: snapshot.format(left, style: style),
                critical: left <= 0
            ))
        }
        if let invoice = figures.pendingInvoice {
            lines.append(BalanceLine(
                id: "claudeapi.pendingInvoice",
                provider: name,
                kind: String(localized: "To be invoiced"),
                amount: snapshot.format(invoice, style: style)
            ))
        }
        return lines
    }

    /// The promotional grant's expiry — the credit's reset — written as the dropdown's
    /// `ClaudePlatformBudgetGauge` writes its reset day ("22 nov"). Nothing once it has passed.
    static func resetDay(_ date: Date?, now: Date) -> String? {
        guard let date, date > now else { return nil }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
