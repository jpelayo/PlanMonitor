import SwiftUI

/// OpenCode's section of the grouped dropdown: the Go windows it reports and the Console budget
/// when there is one, one line each. Reads only OpenCode's own view model.
struct OpenCodeGroupedSection: View {
    @Bindable var viewModel: OpenCodeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch viewModel.connectionState {
            case .connected:
                GroupedSectionHeader(
                    title: ProviderID.opencode.displayName,
                    alert: alert,
                    staleSince: viewModel.isStale ? viewModel.lastUpdated : nil,
                    isDemo: viewModel.isDemoMode
                )
                rows
            case .invalidKey(_, let reason):
                // A refused key: no figures, the reason and the way out.
                GroupedSectionHeader(
                    title: ProviderID.opencode.displayName,
                    actionTitle: String(localized: "Replace key"),
                    action: { WindowRouter.shared.open(.connectOpenCode) }
                )
                if !reason.isEmpty {
                    GroupedSectionNote(text: reason, tint: .red)
                }
            case .validating:
                GroupedSectionHeader(title: ProviderID.opencode.displayName)
                ProgressView().controlSize(.small)
            case .disconnected:
                GroupedSectionHeader(
                    title: ProviderID.opencode.displayName,
                    actionTitle: String(localized: "Connect"),
                    action: { WindowRouter.shared.open(.connectOpenCode) }
                )
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
                GroupedSectionNote(text: String(localized: "No usage data yet"))
            }
        } else {
            // The same bars as `OpenCodeMenuBarView.goSection`: the 5-hour plain, the weekly with
            // seven segments, the monthly one per day of its month, both with the pace marker.
            if let window = snapshot.go?.rolling {
                windowRow(String(localized: "5-hour limit"), window)
            }
            if let window = snapshot.go?.weekly {
                windowRow(
                    String(localized: "Weekly limit"),
                    window,
                    segments: 7,
                    duration: UsageWindowKind.sevenDays
                )
            }
            if let window = snapshot.go?.monthly {
                windowRow(
                    String(localized: "Monthly limit"),
                    window,
                    segments: OpenCodeGoUsage.monthlyDays(endingAt: window.resetsAt),
                    duration: OpenCodeGoUsage.monthlyDuration(endingAt: window.resetsAt)
                )
            }
            if snapshot.budget != nil, let used = snapshot.usedFraction {
                CompactGaugeRow(
                    title: snapshot.isWorkspaceTotal
                        ? String(localized: "Workspace spend this month")
                        : String(localized: "Spend this month"),
                    fraction: used,
                    // A reached budget is critical whatever the arithmetic says, as on the bar.
                    color: OpenCodeSeverity(snapshot.exceeded ? 1 : used).color,
                    resetsAt: snapshot.resetsAt
                )
            }
            if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            }
        }
    }

    /// `OpenCodeWindowCard`'s bar: segmented with the pace marker when it has segments, plain
    /// otherwise.
    private func windowRow(
        _ title: String,
        _ window: OpenCodeGoWindow,
        segments: Int? = nil,
        duration: TimeInterval? = nil
    ) -> some View {
        let used = window.effectivePercent / 100
        return CompactGaugeRow(
            title: title,
            fraction: used,
            color: OpenCodeSeverity(used).color,
            resetsAt: window.resetsAt,
            segments: segments,
            marker: UsageWindowKind.elapsedFraction(resetsAt: window.resetsAt, duration: duration)
        )
    }

    /// The same mapping as the dropdown's pill; operational shows nothing here.
    private var alert: GroupedSectionHeader.Alert? {
        switch viewModel.displayedSystemStatus {
        case .operational: nil
        case .degraded: .init(title: String(localized: "OpenCode degraded"), isOutage: false)
        case .outage: .init(title: String(localized: "OpenCode outage"), isOutage: true)
        }
    }
}
