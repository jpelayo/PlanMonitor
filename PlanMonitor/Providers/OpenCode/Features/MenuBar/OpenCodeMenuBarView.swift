import SwiftUI

/// The OpenCode dropdown. House geometry (320pt, 16pt insets) and header order: title, identity
/// with the demo marker, the session time line carrying the status pill.
///
/// Grok's shape on top — the Go subscription's 5-hour, weekly and monthly windows, each a card with
/// its reset, used % as every dropdown gauge shows — and the money below: this month's Console
/// spend against the member's budget, in the four-line money layout, then plain figures on where
/// the budget comes from and what the spend counts. That caption matters: budgets leave out Go
/// usage within the plan, so a Go-only month reads $0, and without saying so the figure looks
/// broken. A half the key cannot read is left out. No log-out row: like OpenRouter, the key is
/// removed from Settings.
struct OpenCodeMenuBarView: View {
    @Bindable var viewModel: OpenCodeViewModel
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.connectionState.showsBudget {
                connectedContent
            } else {
                disconnectedContent
            }
        }
        .frame(width: 320)
        .padding(.bottom, 10)
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedContent: some View {
        header
            .padding()

        Divider()

        VStack(alignment: .leading, spacing: 12) {
            if case .invalidKey(_, let reason) = viewModel.connectionState {
                banner(reason)
            }
            if viewModel.snapshot.isEmpty {
                Text(String(localized: "No usage data yet"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                if let go = viewModel.snapshot.go {
                    goSection(go)
                    Divider()
                }
                if viewModel.snapshot.hasSpend {
                    spendGauge
                    Divider()
                    additionalInfo
                } else if !viewModel.snapshot.budgetsReadable {
                    Text(String(localized: "Give this key Budgets › Read to see Console spend."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()

        statusRows

        Divider()

        SharedMenuFooter(
            providers: providers,
            preferences: preferences,
            isRefreshing: viewModel.isLoading,
            nextRefreshAt: viewModel.nextRefreshAt,
            refreshAction: { await viewModel.refreshUsage() },
            refreshEnabled: !viewModel.isDemoMode
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "PlanMonitor for OpenCode"))
                .font(.headline)

            if let identity = viewModel.identityLabel {
                HStack(spacing: 4) {
                    Text(identity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if viewModel.isDemoMode {
                        Text(verbatim: "• \(String(localized: "Demo"))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            SessionTimeLine(text: viewModel.dailySessionFormatted) {
                statusPill
            }
        }
    }

    /// A link to the status page, styled as itself: `.plain` keeps the capsule exactly as drawn.
    private var statusPill: some View {
        let status = viewModel.displayedSystemStatus
        return Button {
            openURL(OpenCodeStatusService.statusPageURL)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color(for: status))
                    .frame(width: 6, height: 6)
                Text(title(for: status))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(color(for: status))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color(for: status).opacity(0.12))
            .clipShape(.capsule)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Open status page"))
    }

    // MARK: - Go

    /// The three windows. The weekly and monthly bars are segmented one per day and carry the pace
    /// marker, each declared with its own length so the marker sits right: a week, and the calendar
    /// month back from the monthly reset. The 5-hour bar stays plain.
    private func goSection(_ go: OpenCodeGoUsage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "OpenCode Go")
                .font(.subheadline.weight(.semibold))
            if let rolling = go.rolling {
                OpenCodeWindowCard(
                    title: String(localized: "5-hour limit"),
                    window: rolling,
                    windowDuration: OpenCodeGoUsage.rollingDuration
                )
            }
            if let weekly = go.weekly {
                OpenCodeWindowCard(
                    title: String(localized: "Weekly limit"),
                    window: weekly,
                    resetMoment: .weekdayAndTime,
                    segments: 7,
                    windowDuration: UsageWindowKind.sevenDays
                )
            }
            if let monthly = go.monthly {
                OpenCodeWindowCard(
                    title: String(localized: "Monthly limit"),
                    window: monthly,
                    resetMoment: .day,
                    segments: OpenCodeGoUsage.monthlyDays(endingAt: monthly.resetsAt),
                    windowDuration: OpenCodeGoUsage.monthlyDuration(endingAt: monthly.resetsAt)
                )
            }
            if go.isRateLimited {
                Text(String(localized: "Go requests are paused until the reset unless Extra usage is on."))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Gauge

    @ViewBuilder
    private var spendGauge: some View {
        let snapshot = viewModel.snapshot
        let budget = snapshot.budget
        OpenCodeBudgetGauge(
            title: snapshot.isWorkspaceTotal
                ? String(localized: "Workspace spend this month")
                : String(localized: "Spend this month"),
            fraction: snapshot.exceeded ? max(1, snapshot.usedFraction ?? 1) : snapshot.usedFraction,
            usedText: snapshot.spent.map(money),
            availableText: budget.map(money),
            remainingText: snapshot.leftUnderBudget.map(money),
            resetsAt: snapshot.resetsAt
        )
    }

    // MARK: - Additional information

    @ViewBuilder
    private var additionalInfo: some View {
        let snapshot = viewModel.snapshot
        VStack(alignment: .leading, spacing: 4) {
            if !snapshot.isWorkspaceTotal {
                infoRow(String(localized: "Budget"), budgetSourceText(snapshot))
            }
            if snapshot.exceeded {
                Text(String(localized: "Budget reached. Requests fail until it resets or an admin raises it."))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(String(localized: "Counts paid models, web search and Go extra usage, not Go usage within your plan."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func budgetSourceText(_ snapshot: OpenCodeSnapshot) -> String {
        guard snapshot.budget != nil else { return String(localized: "None") }
        switch snapshot.budgetSource {
        case .custom: return String(localized: "Your own")
        case .default: return String(localized: "Workspace default")
        case nil: return "—"
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private func banner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            Text(message).font(.caption)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Every amount in the dropdown, written with the user's currency style.
    private func money(_ amount: Decimal) -> String {
        OpenCodeMoney.format(amount, style: viewModel.currencyStyle)
    }

    // MARK: - Status rows

    /// Error, then degraded, then staleness. No "Updated …" line: the footer's countdown already
    /// says when the next poll is.
    @ViewBuilder
    private var statusRows: some View {
        if let error = viewModel.errorMessage, !isShownInBanner(error) {
            statusText(error, tint: .red)
        } else if let degraded = viewModel.degradedMessage {
            statusText(degraded, tint: .orange)
        }
        if let updated = viewModel.lastUpdated, viewModel.isStale {
            statusText(String(localized: "Stale — last updated \(relative(updated))"), tint: .secondary)
        }
    }

    private func isShownInBanner(_ message: String) -> Bool {
        if case .invalidKey(_, let reason) = viewModel.connectionState { return reason == message }
        return false
    }

    private func statusText(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    // MARK: - Disconnected

    @ViewBuilder
    private var disconnectedContent: some View {
        VStack(spacing: 16) {
            SignedOutHeader(
                symbolName: OpenCodeMenuBarLabel.symbolName,
                fallbackSymbol: "ring.dashed",
                title: String(localized: "Connect OpenCode"),
                subtitle: String(localized: "Track your OpenCode Go limits and spend from the menu bar"),
                actionTitle: String(localized: "Connect"),
                action: { WindowRouter.shared.open(.connectOpenCode) }
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

    // MARK: - Helpers

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func color(for status: OpenCodeSystemStatus) -> Color {
        switch status {
        case .operational: .green
        case .degraded: .orange
        case .outage: .red
        }
    }

    private func title(for status: OpenCodeSystemStatus) -> String {
        switch status {
        case .operational: String(localized: "OpenCode operational")
        case .degraded: String(localized: "OpenCode degraded")
        case .outage: String(localized: "OpenCode outage")
        }
    }
}
