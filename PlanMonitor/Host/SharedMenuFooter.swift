import AppKit
import SwiftUI

/// The fixed ending of every provider dropdown: Refresh, Settings, provider checkboxes,
/// Launch at login, provider-local Sign Out (never for OpenRouter), Quit. Providers cannot add
/// rows here; anything provider-specific belongs in their usage block.
struct SharedMenuFooter: View {
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences

    let isRefreshing: Bool
    /// The polling service's real next deadline, or `nil` while none is scheduled.
    let nextRefreshAt: Date?
    let refreshAction: (@MainActor () async -> Void)?
    var refreshEnabled = true
    var signOutAction: (@MainActor () async -> Void)?

    @State private var refreshInFlight = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            if let refreshAction {
                actionRow(String(localized: "Refresh"), systemImage: "arrow.clockwise") {
                    guard !refreshInFlight else { return }
                    refreshInFlight = true
                    Task {
                        await refreshAction()
                        refreshInFlight = false
                    }
                } trailing: {
                    ZStack {
                        if isRefreshing || refreshInFlight {
                            // `.controlSize(.small)` and not `.scaleEffect`: a spinning
                            // `ProgressView` is a 32pt box on macOS, and `scaleEffect` shrinks only
                            // the drawing, leaving the full box in the layout — which is what made
                            // the row grow every time a refresh started.
                            ProgressView()
                                .controlSize(.small)
                        } else if let nextRefreshAt, nextRefreshAt > Date() {
                            // `.timer` counts down to the date and never past it.
                            Text(nextRefreshAt, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxHeight: Self.trailingSlotHeight)
                }
                .disabled(!refreshEnabled || refreshInFlight)

                Divider()
            }

            Button {
                // SwiftUI's own action first; the responder-chain action is the fallback
                // for the case where the hosted view has no app environment.
                openSettings()
                WindowRouter.shared.openSettings()
            } label: {
                rowLabel(String(localized: "Settings..."), systemImage: "gear")
            }
            .buttonStyle(.plain)

            Divider()

            ProviderControlsRow(providers: providers)

            Divider()

            HStack {
                Label(String(localized: "Launch at login"), systemImage: "power.circle")
                Spacer()
                Toggle(isOn: $preferences.launchAtLogin) { EmptyView() }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let signOutAction {
                Divider()
                actionRow(
                    String(localized: "Sign Out"),
                    systemImage: "rectangle.portrait.and.arrow.right"
                ) {
                    Task { await signOutAction() }
                }
            }

            Divider()

            actionRow(String(localized: "Quit"), systemImage: "power") {
                AppRuntimeState.prepareForUserInitiatedTermination(reason: "quit")
                NSApp.terminate(nil)
            }
        }
    }

    /// Caps the Refresh row's trailing slot so swapping the countdown for the spinner cannot
    /// change the row's height. Below the row label's own line height, so an empty slot — no
    /// countdown scheduled — leaves the row exactly as it is today.
    private static let trailingSlotHeight: CGFloat = 16

    private func rowLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func actionRow<Trailing: View>(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
