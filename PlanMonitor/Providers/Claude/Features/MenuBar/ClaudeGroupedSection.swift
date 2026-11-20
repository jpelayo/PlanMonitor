import SwiftUI

/// Claude's section of the grouped dropdown: every bar its own dropdown draws, one line each,
/// with the same segments and pace marker. Reads only Claude's own view model.
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
            // Every bar `ClaudeMenuBarView` draws, in its order, titles, conditions and bars.
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
            if let used = usage.sevenDayOpusUtilization {
                weeklyRow(String(localized: "Opus (7-Day)"), used, usage.sevenDayOpusResetsAt)
            }
            // The dynamic weekly scoped window (Fable today).
            if let label = usage.sevenDayScopedLabel, let used = usage.sevenDayScopedUtilization {
                weeklyRow(String(format: String(localized: "%@ (7-Day)"), label), used, usage.sevenDayScopedResetsAt)
            }
            if let used = usage.sevenDaySonnetUtilization {
                weeklyRow(String(localized: "Sonnet (7-Day)"), used, usage.sevenDaySonnetResetsAt)
            }
            if let used = usage.extraUsageUtilization, !usage.hasExtraUsageAccounting {
                CompactGaugeRow(
                    title: String(localized: "Extra Credits"),
                    fraction: used / 100,
                    color: colorForUtilization(used),
                    resetsAt: usage.extraUsageResetsAt
                )
            }
            // The money bars: plain, no reset, under the dropdown's own conditions.
            if usage.hasAvailablePrepaidCredits,
               usage.prepaidCreditsRemainingFormatted != nil,
               let used = usage.prepaidCreditsUtilization {
                CompactGaugeRow(
                    title: String(localized: usage.prepaidCreditsArePromotional == true
                        ? "Promotional Credits"
                        : "Credit Balance"),
                    fraction: min(used / 100, 1),
                    color: colorForUtilization(used)
                )
            }
            if usage.hasAvailablePaidCredits,
               usage.paidCreditsRemainingFormatted != nil,
               usage.paidCreditsSpentValueFormatted != nil,
               usage.paidCreditsTotalFormatted != nil,
               let used = usage.paidCreditsUtilization {
                CompactGaugeRow(
                    title: String(localized: "Prepaid Credits"),
                    fraction: min(used / 100, 1),
                    color: colorForUtilization(used)
                )
            }
            if usage.pendingInvoiceFormatted != nil,
               usage.overageLimitFormatted != nil,
               let used = usage.pendingInvoiceUtilization {
                CompactGaugeRow(
                    title: String(localized: "Invoiceable Spend"),
                    fraction: min(used / 100, 1),
                    color: colorForUtilization(used)
                )
            }
            if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            }
        }
    }

    /// A 7-day window, drawn as the dropdown's `.multiDay` `usageBlock` draws it: seven segments
    /// and the white pace marker.
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
        switch viewModel.displayedClaudeSystemStatus {
        case .operational: nil
        case .degraded: .init(title: String(localized: "Claude degraded"), isOutage: false)
        case .outage: .init(title: String(localized: "Claude outage"), isOutage: true)
        }
    }
}
