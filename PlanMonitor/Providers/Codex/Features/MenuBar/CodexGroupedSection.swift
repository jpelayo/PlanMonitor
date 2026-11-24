import SwiftUI

/// Codex's section of the grouped dropdown: every bar its own dropdown draws, one line each, with
/// the same segments and pace marker. Reads only Codex's own view model.
struct CodexGroupedSection: View {
    @Bindable var viewModel: CodexUsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.authState.isAuthenticated {
                GroupedSectionHeader(
                    title: ProviderID.codex.displayName,
                    detail: viewModel.usageData.planTier.displayName,
                    alert: alert,
                    isDemo: viewModel.isDemoMode
                )
                rows
            } else {
                GroupedSectionHeader(
                    title: ProviderID.codex.displayName,
                    actionTitle: String(localized: "Sign In"),
                    action: { WindowRouter.shared.open(.loginCodex) }
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
        if !usage.hasUsageLimits {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            } else {
                GroupedSectionNote(text: String(localized: "No usage limits available"))
            }
        } else {
            // Every bar `CodexMenuBarView` draws, in its order, titles, conditions and bars.
            if let used = usage.fiveHourUtilization {
                CompactGaugeRow(
                    title: String(localized: "5-Hour Limit"),
                    fraction: used / 100,
                    color: colorForUtilization(used),
                    resetsAt: usage.fiveHourResetsAt
                )
            }
            if let used = usage.sevenDayUtilization {
                weeklyRow(String(localized: "7-Day Limit"), used, usage.sevenDayResetsAt)
            }
            // Slot 3 is the model-scoped FIVE-HOUR bucket (the `sevenDayOpus` name is a donor
            // leftover): plain bar, as in the dropdown.
            if let used = usage.sevenDayOpusUtilization {
                CompactGaugeRow(
                    title: usage.sevenDayOpusName ?? String(localized: "Additional 5-Hour Limit"),
                    fraction: used / 100,
                    color: colorForUtilization(used),
                    resetsAt: usage.sevenDayOpusResetsAt
                )
            }
            // Slot 4 is the model-scoped WEEKLY bucket: segmented, with the pace marker.
            if let used = usage.sevenDaySonnetUtilization {
                weeklyRow(
                    usage.sevenDaySonnetName ?? String(localized: "Additional Weekly Limit"),
                    used,
                    usage.sevenDaySonnetResetsAt
                )
            }
            if let used = usage.extraUsageUtilization {
                CompactGaugeRow(
                    title: usage.extraUsageName ?? String(localized: "Code Review"),
                    fraction: used / 100,
                    color: colorForUtilization(used),
                    resetsAt: usage.extraUsageResetsAt
                )
            }
            if usage.overageEnabled == true,
               usage.overageUsedFormatted != nil,
               usage.overageLimitFormatted != nil,
               usage.overageRemainingFormatted != nil,
               let used = usage.overageUtilization {
                CompactGaugeRow(
                    title: String(localized: "Extra Credits (Prepaid)"),
                    fraction: min(used / 100, 1),
                    color: colorForUtilization(used)
                )
            }
            if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            }
        }
    }

    /// A weekly window, drawn as the dropdown draws it: seven segments and the white pace marker.
    private func weeklyRow(_ title: String, _ used: Double, _ resetsAt: Date?) -> some View {
        CompactGaugeRow(
            title: title,
            fraction: used / 100,
            color: colorForUtilization(used),
            resetsAt: resetsAt,
            segments: 7,
            marker: UsageWindowKind.elapsedFraction(resetsAt: resetsAt, duration: UsageWindowKind.sevenDays)
        )
    }

    /// The same mapping as the dropdown's pill; operational shows nothing here.
    private var alert: GroupedSectionHeader.Alert? {
        switch viewModel.displayedCodexSystemStatus {
        case .operational: nil
        case .degraded: .init(title: String(localized: "Codex degraded"), isOutage: false, statusPage: CodexStatusService.statusPageURL)
        case .outage: .init(title: String(localized: "Codex outage"), isOutage: true, statusPage: CodexStatusService.statusPageURL)
        }
    }
}
