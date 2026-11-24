import SwiftUI

/// Grok's section of the grouped dropdown: the bar its dropdown draws, one line. Reads only
/// Grok's own view model. Like the dropdown since 2026-11-19, it never opens a window by itself.
struct GrokGroupedSection: View {
    @Bindable var viewModel: GrokUsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.authState.showsUsage {
                GroupedSectionHeader(
                    title: ProviderID.grok.displayName,
                    detail: viewModel.usageData.planDisplayName,
                    alert: alert,
                    staleSince: viewModel.isStale ? viewModel.lastUpdated : nil,
                    isDemo: viewModel.isDemoMode
                )
                rows
            } else {
                GroupedSectionHeader(
                    title: ProviderID.grok.displayName,
                    actionTitle: String(localized: "Sign In"),
                    action: {
                        // As the dropdown does: sign out completely before the login web view
                        // exists, so the two never race on credentials.
                        Task {
                            await viewModel.logout()
                            WindowRouter.shared.open(.loginGrok)
                        }
                    }
                )
                if let error = viewModel.errorMessage {
                    GroupedSectionNote(text: error, tint: .red)
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        // The same either/or as `GrokMenuBarView.usageSection`: the weekly pool (seven segments,
        // the white pace marker) or, without one, the monthly allowance (plain bar).
        let usage = viewModel.usageData
        if let used = usage.usedPercent {
            CompactGaugeRow(
                title: String(localized: "Weekly SuperGrok Limit"),
                fraction: used / 100,
                color: colorForUtilization(used),
                resetsAt: usage.weeklyResetsAt,
                segments: 7,
                marker: UsageWindowKind.elapsedFraction(resetsAt: usage.weeklyResetsAt, duration: 7 * 24 * 3600)
            )
            if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            }
        } else if let limit = usage.monthlyLimit, let used = usage.monthlyUsed, limit > 0 {
            let percent = min((used / limit) * 100, 100)
            CompactGaugeRow(
                title: String(localized: "Monthly included"),
                fraction: percent / 100,
                color: colorForUtilization(percent),
                resetsAt: usage.monthlyResetsAt
            )
            if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            }
        } else if viewModel.isLoading {
            ProgressView().controlSize(.small)
        } else if let error = viewModel.errorMessage {
            GroupedSectionNote(text: error, tint: .red)
        } else {
            GroupedSectionNote(text: String(localized: "No usage limits available"))
        }
    }

    /// The same mapping as the dropdown's pill; operational shows nothing here.
    private var alert: GroupedSectionHeader.Alert? {
        switch viewModel.visibleGrokSystemStatus {
        case nil, .operational?: nil
        case .degraded?: .init(title: String(localized: "Grok degraded"), isOutage: false, statusPage: GrokStatusService.statusPageURL)
        case .outage?: .init(title: String(localized: "Grok outage"), isOutage: true, statusPage: GrokStatusService.statusPageURL)
        }
    }
}
