import SwiftUI

/// Google AI's section of the grouped dropdown: every bar its own dropdown draws, one per agy
/// bucket, titled "<group> · <window>", with the same segments and pace marker. Reads only its own
/// view model.
struct GoogleAIGroupedSection: View {
    @Bindable var viewModel: GoogleAIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.needsSetup {
                GroupedSectionHeader(
                    title: ProviderID.googleai.displayName,
                    actionTitle: String(localized: "Set up…"),
                    action: { WindowRouter.shared.open(.setupGoogleAI) }
                )
            } else {
                GroupedSectionHeader(
                    title: ProviderID.googleai.displayName,
                    staleSince: viewModel.isStale ? viewModel.lastUpdated : nil,
                    isDemo: viewModel.isDemoMode
                )
                rows
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if viewModel.usage.isEmpty {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            } else {
                GroupedSectionNote(text: String(localized: "No usage data yet"))
            }
        } else {
            ForEach(viewModel.usage.buckets) { bucket in
                CompactGaugeRow(
                    title: "\(bucket.group) · \(windowName(bucket))",
                    fraction: bucket.used,
                    color: GoogleAISeverity(bucket.used).color,
                    resetsAt: bucket.shownReset,
                    segments: bucket.kind == .weekly ? 7 : nil,
                    marker: bucket.kind == .weekly ? bucket.paceFraction() : nil
                )
            }
            if let error = viewModel.errorMessage {
                GroupedSectionNote(text: error, tint: .red)
            }
        }
    }

    private func windowName(_ bucket: GoogleAIBucket) -> String {
        switch bucket.kind {
        case .fiveHour: String(localized: "5-hour")
        case .weekly: String(localized: "Weekly")
        case .other: bucket.name
        }
    }
}
