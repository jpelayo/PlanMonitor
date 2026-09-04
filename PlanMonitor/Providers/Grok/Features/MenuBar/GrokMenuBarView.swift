import SwiftUI

struct GrokMenuBarView: View {
    @Bindable var viewModel: GrokUsageViewModel
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.authState.showsUsage {
                authenticatedContent
            } else {
                unauthenticatedContent
            }
        }
        .frame(width: 320)
        .padding(.bottom, 10)
        .onAppear {
            presentLoginWindowIfNeeded()
        }
        .onChange(of: viewModel.needsUsageAuthorization) { _, needed in
            if needed {
                presentLoginWindowIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        header
            .padding()

        Divider()

        usageSection
            .padding()

        if viewModel.usageData.hasExtraCredits {
            Divider()
            extraCredits
                .padding()
        }

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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "PlanMonitor for Grok"))
                    .font(.headline)
                Spacer()
                if let plan = viewModel.usageData.planDisplayName {
                    Text(plan)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .clipShape(.capsule)
                }
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
                    let status = viewModel.displayedGrokSystemStatus
                    HStack(spacing: 5) {
                        Circle()
                            .fill(colorForGrokStatus(status))
                            .frame(width: 6, height: 6)
                        Text(titleForGrokStatus(status))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(colorForGrokStatus(status))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(colorForGrokStatus(status).opacity(0.12))
                    .clipShape(.capsule)
                    .fixedSize(horizontal: true, vertical: false)
                }
                ExtraExpenditureLine(
                    enabled: extraExpenditureEnabled,
                    hasStartedSpend: extraExpenditureStarted,
                    usedFormatted: viewModel.usageData.onDemandUsed.map(Self.usd),
                    limitFormatted: viewModel.usageData.onDemandCap.map(Self.usd)
                )
            }
            if case .reimportRequired(let message) = viewModel.authState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Grok's pay-as-you-go is automatic recharge, which its billing page calls "Recarga
    /// automática". An on-demand cap can sit on the account with recharge switched off, so
    /// the cap alone must not read as enabled — only the top-up method decides.
    private var extraExpenditureEnabled: Bool? {
        guard viewModel.usageData.topUpMethod != nil else { return nil }
        return viewModel.usageData.isAutoTopUpEnabled
    }

    private var extraExpenditureStarted: Bool {
        let data = viewModel.usageData
        return (data.onDemandUsed ?? 0) > 0 && (data.onDemandCap ?? 0) > 0
    }

    nonisolated private static func usd(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD"))
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let used = viewModel.usageData.usedPercent {
                GrokUsageProgressCard(
                    title: String(localized: "Weekly SuperGrok Limit"),
                    usedPercent: used,
                    resetsAt: viewModel.usageData.weeklyResetsAt,
                    showResetMoment: true,
                    segments: 7,
                    windowDuration: 7 * 24 * 3600
                )
            } else if let limit = viewModel.usageData.monthlyLimit,
                      let used = viewModel.usageData.monthlyUsed,
                      limit > 0 {
                GrokUsageProgressCard(
                    title: String(localized: "Monthly included"),
                    usedPercent: min((used / limit) * 100, 100),
                    resetsAt: viewModel.usageData.monthlyResetsAt,
                )
            } else if viewModel.needsUsageAuthorization {
                VStack(spacing: 6) {
                    if let code = viewModel.pendingUserCode {
                        Text(code)
                            .font(.title3.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                        Text(String(localized: "Confirm letters match and press Continue"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(String(localized: "Usage access still needs approval."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(String(localized: "Approve usage access")) {
                        presentLoginWindow()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text(String(localized: "No usage limits available"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(viewModel.usageData.sortedProducts) { item in
                GrokProductUsageRow(item: item)
            }
        }
    }

    private var extraCredits: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Extra usage credits"))
                .font(.subheadline)
            if let balance = viewModel.usageData.prepaidBalance {
                Text(balance, format: .currency(code: "USD"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if viewModel.usageData.isAutoTopUpEnabled {
                Text(String(localized: "Auto top-up is on"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var unauthenticatedContent: some View {
        VStack(spacing: 16) {
            SignedOutHeader(
                symbolName: "guaranisign.ring.dashed",
                fallbackSymbol: "ring.dashed",
                title: String(localized: "Sign in to Grok"),
                subtitle: String(localized: "Track your SuperGrok weekly usage from the menu bar"),
                actionTitle: String(localized: "Sign In"),
                action: {
                    // Sign out completely before the login WebView exists, so the two never
                    // race on cookies or credentials.
                    Task {
                        await viewModel.logout()
                        WindowRouter.shared.open(.loginGrok)
                    }
                }
            )

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
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

    private func colorForGrokStatus(_ status: GrokSystemStatus) -> Color {
        switch status {
        case .operational:
            .green
        case .degraded:
            .orange
        case .outage:
            .red
        }
    }

    private func titleForGrokStatus(_ status: GrokSystemStatus) -> String {
        switch status {
        case .operational:
            String(localized: "Grok operational")
        case .degraded:
            String(localized: "Grok degraded")
        case .outage:
            String(localized: "Grok outage")
        }
    }

    private func presentLoginWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        WindowRouter.shared.open(.loginGrok)
    }

    private func presentLoginWindowIfNeeded() {
        guard viewModel.needsUsageAuthorization, !viewModel.isDemoMode else { return }
        presentLoginWindow()
    }
}
