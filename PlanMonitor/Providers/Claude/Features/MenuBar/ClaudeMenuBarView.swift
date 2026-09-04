//
//  ClaudeMenuBarView.swift
//  PlanTracker
//

import SwiftUI

struct ClaudeMenuBarView: View {
    @Bindable var viewModel: ClaudeUsageViewModel
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences
    let reviewerMode: ReviewerMode
    @State private var tapCount = 0
    @State private var lastTapTime = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.authState.isAuthenticated {
                authenticatedContent
            } else {
                unauthenticatedContent
            }
        }
        .frame(width: 320)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        // Header
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "PlanMonitor for Claude"))
                    .font(.headline)
                Spacer()
                Text(viewModel.usageData.planDisplayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2))
                    .clipShape(.capsule)
            }

            if let email = viewModel.authState.email {
                HStack(spacing: 4) {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if viewModel.isDemoMode {
                        Text(verbatim: "• \(String(localized: "Demo"))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                SessionTimeLine(text: viewModel.dailySessionFormatted) {
                    let status = viewModel.displayedClaudeSystemStatus
                    HStack(spacing: 5) {
                        Circle()
                            .fill(colorForClaudeStatus(status))
                            .frame(width: 6, height: 6)
                        Text(titleForClaudeStatus(status))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(colorForClaudeStatus(status))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(colorForClaudeStatus(status).opacity(0.12))
                    .clipShape(.capsule)
                    .fixedSize(horizontal: true, vertical: false)
                }
                ExtraExpenditureLine(
                    enabled: viewModel.usageData.overageEnabled,
                    hasStartedSpend: viewModel.usageData.hasStartedExtraUsageSpend,
                    usedFormatted: viewModel.usageData.overageUsedFormatted,
                    limitFormatted: viewModel.usageData.overageLimitFormatted
                )
            }
        }
        .padding()

        Divider()

        // Usage Info
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.usageData.fiveHourUtilization == nil && viewModel.usageData.sevenDayUtilization == nil {
                // No usage data available (free tier or limits not applicable)
                Text(String(localized: "No usage limits available"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                // 5-Hour Usage
                if let utilization = viewModel.usageData.fiveHourUtilization {
                    usageBlock(
                        title: String(localized: "5-Hour Limit"),
                        utilization: utilization,
                        countdown: viewModel.usageData.formattedFiveHourReset
                    )
                }

                // 7-Day Usage (Pro)
                if let utilization = viewModel.usageData.sevenDayUtilization {
                    usageBlock(
                        title: String(localized: "7-Day Limit"),
                        utilization: utilization,
                        countdown: viewModel.usageData.formattedSevenDayReset,
                        moment: viewModel.usageData.sevenDayResetsAt,
                        window: .multiDay
                    )
                }

                // 7-Day Opus Usage
                if let utilization = viewModel.usageData.sevenDayOpusUtilization {
                    usageBlock(
                        title: String(localized: "Opus (7-Day)"),
                        utilization: utilization,
                        countdown: viewModel.usageData.formattedSevenDayOpusReset,
                        moment: viewModel.usageData.sevenDayOpusResetsAt,
                        window: .multiDay
                    )
                }

                // Dynamic weekly scoped usage (ex: Fable)
                if let label = viewModel.usageData.sevenDayScopedLabel,
                   let utilization = viewModel.usageData.sevenDayScopedUtilization {
                    usageBlock(
                        title: scopedSevenDayTitle(label),
                        utilization: utilization,
                        countdown: viewModel.usageData.formattedSevenDayScopedReset,
                        moment: viewModel.usageData.sevenDayScopedResetsAt,
                        window: .multiDay
                    )
                }

                // 7-Day Sonnet Usage
                if let utilization = viewModel.usageData.sevenDaySonnetUtilization {
                    usageBlock(
                        title: String(localized: "Sonnet (7-Day)"),
                        utilization: utilization,
                        countdown: viewModel.usageData.formattedSevenDaySonnetReset,
                        moment: viewModel.usageData.sevenDaySonnetResetsAt,
                        window: .multiDay
                    )
                }

                // Extra Usage (Add-on Credits)
                if let utilization = viewModel.usageData.extraUsageUtilization,
                   !viewModel.usageData.hasExtraUsageAccounting {
                    usageBlock(
                        title: String(localized: "Extra Credits"),
                        utilization: utilization,
                        countdown: viewModel.usageData.formattedExtraUsageReset
                    )
                }

                // This is the sole money-balance visualization.
                if viewModel.usageData.hasAvailablePrepaidCredits,
                   let remaining = viewModel.usageData.prepaidCreditsRemainingFormatted {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: viewModel.usageData.prepaidCreditsArePromotional == true
                                ? "Promotional Credits"
                                : "Credit Balance"))
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 4)
                            if let spent = viewModel.usageData.prepaidCreditsSpentValueFormatted,
                               let total = viewModel.usageData.prepaidCreditsTotalFormatted {
                                HStack(spacing: 2) {
                                    Text(spent)
                                        .foregroundStyle(.red)
                                    Text(verbatim: "/")
                                        .foregroundStyle(.secondary)
                                    Text(total)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                            } else {
                                Text(remaining)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .layoutPriority(1)
                            }
                        }

                        if let utilization = viewModel.usageData.prepaidCreditsUtilization {
                            UsageBar(fraction: min(utilization / 100, 1.0), color: colorForUtilization(utilization))
                            Text(verbatim: "\(Int(100 - utilization))% \(String(localized: "remaining")) (\(remaining))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: "\(String(localized: "remaining")) \(remaining)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                    }
                }

                if viewModel.usageData.hasAvailablePaidCredits,
                   let remaining = viewModel.usageData.paidCreditsRemainingFormatted,
                   let spent = viewModel.usageData.paidCreditsSpentValueFormatted,
                   let total = viewModel.usageData.paidCreditsTotalFormatted {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Prepaid Credits"))
                                .font(.subheadline)
                            Spacer(minLength: 4)
                            HStack(spacing: 2) {
                                Text(spent).foregroundStyle(.red)
                                Text(verbatim: "/").foregroundStyle(.secondary)
                                Text(total).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        if let utilization = viewModel.usageData.paidCreditsUtilization {
                            UsageBar(fraction: min(utilization / 100, 1), color: colorForUtilization(utilization))
                            Text(verbatim: "\(Int(100 - utilization))% \(String(localized: "remaining")) (\(remaining))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let autoReload = viewModel.usageData.prepaidAutoReloadEnabled {
                            Label(
                                String(localized: autoReload ? "Auto-reload enabled" : "No auto-reload"),
                                systemImage: autoReload ? "arrow.clockwise.circle.fill" : "info.circle"
                            )
                            .font(.caption2)
                            .foregroundStyle(autoReload ? .orange : .secondary)
                        }
                    }
                }

                if let invoice = viewModel.usageData.pendingInvoiceFormatted,
                   let limit = viewModel.usageData.overageLimitFormatted,
                   let utilization = viewModel.usageData.pendingInvoiceUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Invoiceable Spend"))
                                .font(.subheadline)
                            Spacer()
                            Text(verbatim: "\(invoice) / \(limit)")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        UsageBar(fraction: min(utilization / 100, 1), color: colorForUtilization(utilization))
                    }
                }

            }
        }
        .padding()

        if let error = viewModel.errorMessage {
            Divider()
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }

        Divider()

        SharedMenuFooter(
            providers: providers,
            preferences: preferences,
            isRefreshing: viewModel.isLoading,
            nextRefreshAt: viewModel.nextRefreshAt,
            refreshAction: { await viewModel.refreshUsage() },
            refreshEnabled: !viewModel.isDemoMode,
            signOutAction: { await viewModel.logout() }
        )
    }

    private func usageBlock(
        title: String,
        utilization: Double,
        countdown: String?,
        moment: Date? = nil,
        window: UsageWindowKind = .unknown
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(verbatim: "\(Int(utilization))% \(String(localized: "used"))")
                    .font(.subheadline)
                    .foregroundStyle(colorForUtilization(utilization))
            }
            if window.showsDailySegments {
                SegmentedUsageBar(
                    fraction: utilization / 100,
                    color: colorForUtilization(utilization),
                    marker: UsageWindowKind.elapsedFraction(
                        resetsAt: moment,
                        duration: UsageWindowKind.sevenDays
                    )
                )
            } else {
                UsageBar(fraction: utilization / 100, color: colorForUtilization(utilization))
            }
            ResetCaption(countdown: countdown, moment: moment)
        }
    }

    @ViewBuilder
    private var unauthenticatedContent: some View {
        VStack(spacing: 16) {
            // Seven taps on the glyph put the whole app into reviewer mode (see ReviewerMode).
            SignedOutHeader(
                symbolName: "cedisign.ring.dashed",
                fallbackSymbol: "ring.dashed",
                title: String(localized: "Sign in to Claude"),
                subtitle: String(localized: "Track your Claude.ai usage from the menu bar"),
                actionTitle: String(localized: "Sign In"),
                action: { WindowRouter.shared.open(.loginClaude) },
                onSymbolTap: handleTap
            )

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Divider()

            SharedMenuFooter(
                providers: providers,
                preferences: preferences,
                isRefreshing: false,
                nextRefreshAt: nil,
                refreshAction: nil
            )
            .padding(.horizontal, -16)
        }
        .padding()
    }

    private func scopedSevenDayTitle(_ label: String) -> String {
        String(format: String(localized: "%@ (7-Day)"), label)
    }

    private func colorForUtilization(_ utilization: Double) -> Color {
        switch utilization {
        case ..<65: .green
        case 65..<90: Color(red: 0.82, green: 0.42, blue: 0.04)
        default: .red
        }
    }

    private func colorForClaudeStatus(_ status: ClaudeSystemStatus) -> Color {
        switch status {
        case .operational:
            .green
        case .degraded:
            .orange
        case .outage:
            .red
        }
    }

    private func titleForClaudeStatus(_ status: ClaudeSystemStatus) -> String {
        switch status {
        case .operational:
            String(localized: "Claude operational")
        case .degraded:
            String(localized: "Claude degraded")
        case .outage:
            String(localized: "Claude outage")
        }
    }

    private func handleTap() {
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)

        // Reset to zero if more than 2 seconds between taps
        if timeSinceLastTap > 2.0 {
            tapCount = 0
        }

        tapCount += 1
        lastTapTime = now

        // Seventh tap: reviewer mode for every provider.
        if tapCount >= 7 {
            reviewerMode.activate()
            tapCount = 0
        }
    }
}
