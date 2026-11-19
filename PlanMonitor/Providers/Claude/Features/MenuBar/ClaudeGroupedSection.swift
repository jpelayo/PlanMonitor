import SwiftUI

/// Claude's section of the grouped dropdown: its 5-hour and weekly windows, one line each.
/// Reads only Claude's own view model; the full dropdown stays the place for everything else.
struct ClaudeGroupedSection: View {
    @Bindable var viewModel: ClaudeUsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.authState.isAuthenticated {
                GroupedSectionHeader(
                    title: ProviderID.claude.displayName,
                    detail: viewModel.usageData.planDisplayName,
                    alert: alert,
                    isDemo: viewModel.isDemoMode
                )
                rows
            } else {
                GroupedSectionHeader(
                    title: ProviderID.claude.displayName,
                    actionTitle: String(localized: "Sign In"),
                    action: { WindowRouter.shared.open(.loginClaude) }
                )
                if let error = viewModel.errorMessage {
                    GroupedSectionNote(text: error, tint: .red)
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let usage = viewModel.usageData
        if usage.fiveHourUtilization == nil, usage.sevenDayUtilization == nil {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            } else {
                GroupedSectionNote(text: String(localized: "No usage limits available"))
            }
        } else {
            if let used = usage.fiveHourUtilization {
                CompactGaugeRow(
                    title: String(localized: "5-hour limit"),
                    fraction: used / 100,
                    color: colorForUtilization(used),
                    resetsAt: usage.fiveHourResetsAt
                )
            }
            if let used = usage.sevenDayUtilization {
                CompactGaugeRow(
                    title: String(localized: "Weekly limit"),
                    fraction: used / 100,
                    color: colorForUtilization(used),
                    resetsAt: usage.sevenDayResetsAt
                )
            }
            if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            }
        }
    }

    /// The same mapping as the dropdown's pill; operational shows nothing here.
    private var alert: GroupedSectionHeader.Alert? {
        switch viewModel.displayedClaudeSystemStatus {
        case .operational: nil
        case .degraded: .init(title: String(localized: "Claude degraded"), isOutage: false)
        case .outage: .init(title: String(localized: "Claude outage"), isOutage: true)
        }
    }
}
