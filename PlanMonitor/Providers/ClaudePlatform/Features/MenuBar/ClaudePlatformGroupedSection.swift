import SwiftUI

/// Claude-API's section of the grouped dropdown: promotional credit used and this month's spend
/// against its ceiling, one line each. Reads only Claude-API's own view model — the console
/// org's figures, never the claude.ai subscription's.
struct ClaudePlatformGroupedSection: View {
    @Bindable var viewModel: ClaudePlatformViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.authState.isAuthenticated {
                GroupedSectionHeader(
                    title: ProviderID.claudeapi.displayName,
                    alert: alert,
                    staleSince: viewModel.isStale ? viewModel.lastUpdated : nil,
                    isDemo: viewModel.isDemoMode
                )
                rows
            } else {
                GroupedSectionHeader(
                    title: ProviderID.claudeapi.displayName,
                    actionTitle: String(localized: "Sign In"),
                    action: { WindowRouter.shared.open(.loginClaudeAPI) }
                )
                if let error = viewModel.errorMessage {
                    GroupedSectionNote(text: error, tint: .red)
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let snapshot = viewModel.snapshot
        if snapshot.isEmpty {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            } else {
                GroupedSectionNote(text: String(localized: "No billing data yet"))
            }
        } else {
            if let used = snapshot.promoUsedFraction {
                CompactGaugeRow(
                    title: String(localized: "Promotional credit"),
                    fraction: used,
                    color: ClaudePlatformSeverity(used).color,
                    resetsAt: snapshot.promoExpiresAt
                )
            }
            if let used = snapshot.spendUsedFraction {
                CompactGaugeRow(
                    title: String(localized: "Spend this month"),
                    fraction: used,
                    color: ClaudePlatformSeverity(used).color,
                    resetsAt: snapshot.spendResetsAt
                )
            }
            if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            }
        }
    }

    /// The same mapping as the dropdown's pill; operational shows nothing here.
    private var alert: GroupedSectionHeader.Alert? {
        switch viewModel.displayedSystemStatus {
        case .operational: nil
        case .degraded: .init(title: String(localized: "Claude degraded"), isOutage: false)
        case .outage: .init(title: String(localized: "Claude outage"), isOutage: true)
        }
    }
}

/// Claude-API's lines in the Balances block: the credit left (promotional and prepaid, expired
/// promotional tranches already dropped), and what is waiting to be invoiced when the account
/// reports it. Written with Claude-API's own currency style; a missing figure is no line, never 0.
enum ClaudePlatformGroupedBalance {
    static func lines(
        snapshot: ClaudePlatformSnapshot,
        isSignedIn: Bool,
        style: CurrencyStyle
    ) -> [BalanceLine] {
        guard isSignedIn else { return [] }
        let figures = snapshot.figures
        var lines: [BalanceLine] = []
        if let left = figures.creditLeft {
            lines.append(BalanceLine(
                id: "claudeapi.creditLeft",
                provider: ProviderID.claudeapi.displayName,
                kind: String(localized: "Credit left"),
                amount: snapshot.format(left, style: style),
                critical: left <= 0
            ))
        }
        if let invoice = figures.pendingInvoice {
            lines.append(BalanceLine(
                id: "claudeapi.pendingInvoice",
                provider: ProviderID.claudeapi.displayName,
                kind: String(localized: "To be invoiced"),
                amount: snapshot.format(invoice, style: style)
            ))
        }
        return lines
    }
}
