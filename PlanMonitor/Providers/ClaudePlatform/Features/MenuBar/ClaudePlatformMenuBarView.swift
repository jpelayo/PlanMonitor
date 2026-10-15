import SwiftUI

/// The Claude-API dropdown. House geometry (320pt, 16pt insets) and header order: title, identity
/// with the demo marker, the session time line carrying the status pill. No plan badge: the only
/// source for one is the codenamed `link-state` path, which nothing shown may depend on. No
/// `ExtraExpenditureLine` — that is for the subscription providers; this one *is* the money.
///
/// Gauges first, every one in the same four-line layout (`ClaudePlatformBudgetGauge`): promotional
/// credit against its grant, spend against the account's own limit (Anthropic's cap when it set
/// none), and prepaid credit, whose bar stays empty because credit bought is not a cap. Then a
/// divider and a section of plain figures: the limits, anything to be invoiced, auto-payment.
/// Figures the console does not report for this account are left out, never shown as zero.
/// Every amount is written in the user's `CurrencyStyle`.
struct ClaudePlatformMenuBarView: View {
    @Bindable var viewModel: ClaudePlatformViewModel
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

    // MARK: - Signed in

    @ViewBuilder
    private var authenticatedContent: some View {
        header
            .padding()

        Divider()

        VStack(alignment: .leading, spacing: 12) {
            if viewModel.snapshot.isEmpty {
                Text(String(localized: "No billing data yet"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                promotionalCredit
                spend
                prepaidCredit
                if hasAdditionalInfo {
                    Divider()
                    additionalInfo
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
            refreshEnabled: !viewModel.isDemoMode,
            signOutAction: { await viewModel.logout() }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "PlanMonitor for Claude-API"))
                .font(.headline)

            if let email = viewModel.authState.email {
                HStack(spacing: 4) {
                    Text(email)
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
                SessionTimeLine(text: viewModel.dailySessionFormatted) {
                    statusPill
                }
            }
        }
    }

    /// A link to the status page, styled as itself: `.plain` keeps the capsule exactly as drawn.
    private var statusPill: some View {
        let status = viewModel.displayedSystemStatus
        return Button {
            openURL(ClaudePlatformStatusService.statusPageURL)
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

    // MARK: - Gauges

    @ViewBuilder
    private var promotionalCredit: some View {
        let snapshot = viewModel.snapshot
        if let granted = snapshot.promoGranted, let remaining = snapshot.promoRemaining {
            ClaudePlatformBudgetGauge(
                title: String(localized: "Promotional credit"),
                fraction: snapshot.promoUsedFraction,
                usedText: money(max(0, granted - remaining)),
                availableText: money(granted),
                remainingText: money(remaining),
                // The grant's own clock: it expires, and the next one replaces it.
                resetsAt: snapshot.promoExpiresAt
            )
        }
    }

    @ViewBuilder
    private var spend: some View {
        let snapshot = viewModel.snapshot
        if let used = snapshot.spendUsed {
            let ceiling = snapshot.spendCeiling
            ClaudePlatformBudgetGauge(
                title: String(localized: "Spend this month"),
                fraction: snapshot.spendUsedFraction,
                usedText: money(used),
                availableText: ceiling.map(money),
                remainingText: ceiling.map { money(max(0, $0 - used)) },
                resetsAt: snapshot.spendResetsAt
            )
        }
    }

    /// Prepaid credit has no grant or cap to measure use against, and no reset: its bar stays
    /// empty and only the balance is filled in.
    @ViewBuilder
    private var prepaidCredit: some View {
        if let prepaid = viewModel.snapshot.prepaidRemaining {
            ClaudePlatformBudgetGauge(
                title: String(localized: "Prepaid credit"),
                fraction: nil,
                usedText: nil,
                availableText: nil,
                remainingText: money(prepaid),
                resetsAt: nil
            )
        }
    }

    // MARK: - Additional information

    private var hasAdditionalInfo: Bool {
        let snapshot = viewModel.snapshot
        return snapshot.notifyLimit != nil || snapshot.pauseLimit != nil || snapshot.enforcedSpendLimit != nil
            || snapshot.pendingInvoice != nil || snapshot.autoRecharge != nil
    }

    /// Plain figures, lowest limit first: label on the left, value on the right.
    @ViewBuilder
    private var additionalInfo: some View {
        let snapshot = viewModel.snapshot
        VStack(alignment: .leading, spacing: 4) {
            if let notify = snapshot.notifyLimit {
                infoRow(String(localized: "Notifies at"), money(notify))
            }
            if let limit = snapshot.pauseLimit {
                infoRow(String(localized: "Your limit"), money(limit))
            }
            if let cap = snapshot.enforcedSpendLimit {
                infoRow(String(localized: "Anthropic's limit"), money(cap))
            }
            if let invoice = snapshot.pendingInvoice {
                infoRow(String(localized: "To be invoiced"), money(invoice))
            }
            if let recharge = snapshot.autoRecharge {
                infoRow(
                    String(localized: "Auto-payment"),
                    recharge.isEnabled ? String(localized: "On") : String(localized: "Off")
                )
                if recharge.isEnabled, let target = recharge.targetAmount {
                    infoRow(String(localized: "Top-up target"), money(target))
                }
                if recharge.isEnabled, let threshold = recharge.thresholdAmount {
                    infoRow(String(localized: "Top-up threshold"), money(threshold))
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    /// Every amount in the dropdown, written with the user's currency style.
    private func money(_ minorUnits: Int) -> String {
        viewModel.snapshot.format(minorUnits, style: viewModel.currencyStyle)
    }

    // MARK: - Status rows

    /// Error, then degraded, then staleness. No "Updated …" line: the footer's countdown already
    /// says when the next poll is, so a fresh snapshot needs no caption — only one three cycles old
    /// does, because the countdown cannot tell that the polls before it failed.
    @ViewBuilder
    private var statusRows: some View {
        if let error = viewModel.errorMessage {
            statusText(error, tint: .red)
        } else if let degraded = viewModel.degradedMessage {
            statusText(degraded, tint: .orange)
        }
        if let updated = viewModel.lastUpdated, viewModel.isStale {
            statusText(String(localized: "Stale — last updated \(relative(updated))"), tint: .secondary)
        }
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

    // MARK: - Signed out

    @ViewBuilder
    private var unauthenticatedContent: some View {
        VStack(spacing: 16) {
            SignedOutHeader(
                symbolName: "eurosign.ring.dashed",
                fallbackSymbol: "ring.dashed",
                title: String(localized: "Sign in to Claude-API"),
                subtitle: String(localized: "Track your API promotional credit and spend from the menu bar"),
                actionTitle: String(localized: "Sign In"),
                action: { WindowRouter.shared.open(.loginClaudeAPI) }
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

    private func color(for status: ClaudePlatformSystemStatus) -> Color {
        switch status {
        case .operational: .green
        case .degraded: .orange
        case .outage: .red
        }
    }

    /// The status page is Claude's own, covering the API and console with everything else, so the
    /// pill says so — and shares the Claude provider's strings.
    private func title(for status: ClaudePlatformSystemStatus) -> String {
        switch status {
        case .operational: String(localized: "Claude operational")
        case .degraded: String(localized: "Claude degraded")
        case .outage: String(localized: "Claude outage")
        }
    }
}
