import Foundation

/// A provider that can show deterministic demo data for App Review.
@MainActor
protocol DemoCapable: AnyObject {
    var isDemoMode: Bool { get }
    /// Stop live work, load demo data, mark the header. Must not persist anything.
    func enterDemo()
}

/// Reviewer mode for the whole app. One gesture — seven taps on the Claude dropdown title —
/// enables every provider and puts each into demo. It is one-way by design: nothing is
/// persisted, so a relaunch is the exit; a provider that signs out leaves demo on its own.
@MainActor
@Observable
final class ReviewerMode {
    private(set) var isActive = false

    private let providers: EnabledProviders
    private let runtimes: [ProviderID: any DemoCapable]

    init(providers: EnabledProviders, runtimes: [ProviderID: any DemoCapable]) {
        self.providers = providers
        self.runtimes = runtimes
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        AppRuntimeState.recordBreadcrumb("reviewer-mode-activated")

        for provider in ProviderID.allCases {
            providers.set(provider, enabled: true)
        }
        for provider in ProviderID.allCases {
            runtimes[provider]?.enterDemo()
        }
    }
}
