import SwiftUI

/// The Google AI dropdown. House geometry (320pt, 16pt insets) and header order: title, source line
/// with the demo marker, the session time line. Then one block per agy group, in agy's order, its
/// name verbatim (Google's product names) over one card per window, the 5-hour one first. No status pill: Google
/// publishes no status for these limits. No log-out row: there is no sign-in to end.
struct GoogleAIMenuBarView: View {
    @Bindable var viewModel: GoogleAIViewModel
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.needsSetup {
                setupContent
            } else {
                usageContent
            }
        }
        .frame(width: 320)
        .padding(.bottom, 10)
    }

    // MARK: - Usage

    @ViewBuilder
    private var usageContent: some View {
        header
            .padding()

        Divider()

        VStack(alignment: .leading, spacing: 12) {
            if viewModel.usage.isEmpty {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else {
                    Text(String(localized: "No usage data yet"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(viewModel.usage.groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: group.name)
                            .font(.subheadline.weight(.semibold))
                        ForEach(group.shownBuckets) { bucket in
                            GoogleAIWindowCard(bucket: bucket)
                        }
                    }
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
            Text(String(localized: "PlanMonitor for Google AI"))
                .font(.headline)
            HStack(spacing: 4) {
                Text(String(localized: "Antigravity limits, read with agy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.isDemoMode {
                    Text(verbatim: "• \(String(localized: "Demo"))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            SessionTimeLine(text: viewModel.dailySessionFormatted) {
                EmptyView()
            }
        }
    }

    // MARK: - Status rows

    @ViewBuilder
    private var statusRows: some View {
        if let error = viewModel.errorMessage {
            statusText(error, tint: .red)
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

    // MARK: - Setup

    @ViewBuilder
    private var setupContent: some View {
        VStack(spacing: 16) {
            SignedOutHeader(
                symbolName: GoogleAIMenuBarLabel.symbolName,
                fallbackSymbol: "ring.dashed",
                title: String(localized: "Set up Google AI"),
                subtitle: String(localized: "Shows your Antigravity limits using the agy command. A small helper script is needed."),
                actionTitle: String(localized: "Set up…"),
                action: { WindowRouter.shared.open(.setupGoogleAI) }
            )

            if viewModel.lastError == .agyNotFound {
                Text(GoogleAIRunError.agyNotFound.message)
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

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
