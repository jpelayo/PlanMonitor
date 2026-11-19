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
            if let window = snapshot.go?.rolling {
                windowRow(String(localized: "5-hour limit"), window)
            }
            if let window = snapshot.go?.weekly {
                windowRow(String(localized: "Weekly limit"), window)
            }
            if let window = snapshot.go?.monthly {
                windowRow(String(localized: "Monthly limit"), window)
            }
            if snapshot.budget != nil, let used = snapshot.usedFraction {
                CompactGaugeRow(
                    title: String(localized: "Budget"),
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

    private func windowRow(_ title: String, _ window: OpenCodeGoWindow) -> some View {
        let used = window.effectivePercent / 100
        return CompactGaugeRow(
            title: title,
            fraction: used,
            color: OpenCodeSeverity(used).color,
            resetsAt: window.resetsAt
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
