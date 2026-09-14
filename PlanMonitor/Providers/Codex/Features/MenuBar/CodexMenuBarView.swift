//
//  CodexMenuBarView.swift
//  PlanTracker
//

import SwiftUI

struct CodexMenuBarView: View {
    @Bindable var viewModel: CodexUsageViewModel
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences
    @Environment(\.openURL) private var openURL

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
                Text(String(localized: "PlanMonitor for Codex"))
                    .font(.headline)
                Spacer()
                Text(viewModel.usageData.planTier.displayName)
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
                    let status = viewModel.displayedCodexSystemStatus
                    // The pill is a link to the status page, styled as itself: `.plain` keeps
                    // the capsule exactly as drawn, and `openURL` hands off to the default browser.
                    Button {
                        openURL(CodexStatusService.statusPageURL)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(colorForCodexStatus(status))
                                .frame(width: 6, height: 6)
                            Text(titleForCodexStatus(status))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(colorForCodexStatus(status))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(colorForCodexStatus(status).opacity(0.12))
                        .clipShape(.capsule)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Open status page"))
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
            if !viewModel.usageData.hasUsageLimits {
                // No usage data available (free tier or limits not applicable)
                Text(String(localized: "No usage limits available"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                // 5-Hour Usage
                if let utilization = viewModel.usageData.fiveHourUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "5-Hour Limit"))
                                .font(.subheadline)
                            Spacer()
                            Text(verbatim: "\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        UsageBar(fraction: utilization / 100, color: colorForUtilization(utilization))
                        ResetCaption(countdown: viewModel.usageData.formattedFiveHourReset)
                    }
                }

                // 7-Day Usage (Pro)
                if let utilization = viewModel.usageData.sevenDayUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "7-Day Limit"))
                                .font(.subheadline)
                            Spacer()
                            Text(verbatim: "\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        SegmentedUsageBar(
                            fraction: utilization / 100,
                            color: colorForUtilization(utilization),
                            marker: UsageWindowKind.elapsedFraction(
                                resetsAt: viewModel.usageData.sevenDayResetsAt,
                                duration: UsageWindowKind.sevenDays
                            )
                        )
                        ResetCaption(
                            countdown: viewModel.usageData.formattedSevenDayReset,
                            moment: viewModel.usageData.sevenDayResetsAt
                        )
                    }
                }

                // Slot 3: the model-scoped FIVE-HOUR bucket (mapLimitsToSlots fills it via
                // modelFiveHourScore). The `sevenDayOpus` field name is a leftover from the
                // Claude donor model — do not read it as a weekly window.
                if let utilization = viewModel.usageData.sevenDayOpusUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(viewModel.usageData.sevenDayOpusName ?? String(localized: "Additional 5-Hour Limit"))
                                .font(.subheadline)
                            Spacer()
                            Text(verbatim: "\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        UsageBar(fraction: utilization / 100, color: colorForUtilization(utilization))
                        ResetCaption(
                            countdown: viewModel.usageData.formattedSevenDayOpusReset,
                            moment: viewModel.usageData.sevenDayOpusResetsAt
                        )
                    }
                }

                // Slot 4: the model-scoped WEEKLY bucket (modelWeeklyScore). The
                // `sevenDaySonnet` field name is likewise inherited from the Claude donor.
                if let utilization = viewModel.usageData.sevenDaySonnetUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(viewModel.usageData.sevenDaySonnetName ?? String(localized: "Additional Weekly Limit"))
                                .font(.subheadline)
                            Spacer()
                            Text(verbatim: "\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        SegmentedUsageBar(
                            fraction: utilization / 100,
                            color: colorForUtilization(utilization),
                            marker: UsageWindowKind.elapsedFraction(
                                resetsAt: viewModel.usageData.sevenDaySonnetResetsAt,
                                duration: UsageWindowKind.sevenDays
                            )
                        )
                        ResetCaption(
                            countdown: viewModel.usageData.formattedSevenDaySonnetReset,
                            moment: viewModel.usageData.sevenDaySonnetResetsAt
                        )
                    }
                }

                // The dedicated fifth slot is Code Review unless the backend names it.
                if let utilization = viewModel.usageData.extraUsageUtilization {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(viewModel.usageData.extraUsageName ?? String(localized: "Code Review"))
                                .font(.subheadline)
                            Spacer()
                            Text(verbatim: "\(Int(utilization))% \(String(localized: "used"))")
                                .font(.subheadline)
                                .foregroundStyle(colorForUtilization(utilization))
                        }
                        UsageBar(fraction: utilization / 100, color: colorForUtilization(utilization))
                        ResetCaption(countdown: viewModel.usageData.formattedExtraUsageReset)
                    }
                }

                // Extra Credits (monthly overage budget)
                if let enabled = viewModel.usageData.overageEnabled, enabled,
                   let used = viewModel.usageData.overageUsedFormatted,
                   let limit = viewModel.usageData.overageLimitFormatted,
                   let utilization = viewModel.usageData.overageUtilization,
                   let remaining = viewModel.usageData.overageRemainingFormatted {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Extra Credits (Prepaid)"))
                                .font(.subheadline)
                            Spacer()
                            HStack(spacing: 2) {
                                Text(used)
                                    .foregroundStyle(.red)
                                Text(verbatim: "/")
                                    .foregroundStyle(.secondary)
                                Text(limit)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                        UsageBar(fraction: min(utilization / 100, 1.0), color: colorForUtilization(utilization))
                        Text(verbatim: "\(Int(100 - utilization))% \(String(localized: "remaining")) (\(remaining))")
                            .font(.caption)
                            .foregroundStyle(viewModel.usageData.overageOutOfCredits == true ? .red : .secondary)

                        // Auto-reload hint
                        if let autoReload = viewModel.usageData.prepaidAutoReloadEnabled {
                            if autoReload {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.caption2)
                                    Text(String(localized: "Auto-reload enabled"))
                                }
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                    Text(String(localized: "No auto-reload"))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
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

    @ViewBuilder
    private var unauthenticatedContent: some View {
        VStack(spacing: 16) {
            SignedOutHeader(
                symbolName: "ring.dashed",
                fallbackSymbol: "ring.dashed",
                title: String(localized: "Sign in to Codex"),
                subtitle: String(localized: "Track your Codex usage from the menu bar"),
                actionTitle: String(localized: "Sign In"),
                action: { WindowRouter.shared.open(.loginCodex) }
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

    private func colorForCodexStatus(_ status: CodexSystemStatus) -> Color {
        switch status {
        case .operational:
            .green
        case .degraded:
            .orange
        case .outage:
            .red
        }
    }

    private func titleForCodexStatus(_ status: CodexSystemStatus) -> String {
        switch status {
        case .operational:
            String(localized: "Codex operational")
        case .degraded:
            String(localized: "Codex degraded")
        case .outage:
            String(localized: "Codex outage")
        }
    }

    private func colorForUtilization(_ utilization: Double) -> Color {
        switch utilization {
        case ..<65: .green
        case 65..<90: Color(red: 0.82, green: 0.42, blue: 0.04)
        default: .red
        }
    }
}
