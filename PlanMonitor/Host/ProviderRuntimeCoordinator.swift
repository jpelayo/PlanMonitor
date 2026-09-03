import Foundation

/// Owns every provider's active/inactive state. Startup, enablement changes, manual refresh,
/// memory pressure and termination all pass through here; nothing else starts or stops a
/// provider. Operations are idempotent and provider-local: one provider failing or hanging
/// cannot hold up another.
@MainActor
final class ProviderRuntimeCoordinator {
    private let runtimes: [ProviderID: any ProviderRuntime]
    private var activeProviders: Set<ProviderID> = []
    /// Serialises enable/disable per provider so a rapid off/on pair cannot interleave.
    private var transitions: [ProviderID: Task<Void, Never>] = [:]
    private var enablementTask: Task<Void, Never>?
    private var memoryPressureTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        claude: ClaudeUsageViewModel,
        codex: CodexUsageViewModel,
        grok: GrokUsageViewModel,
        openRouter: OpenRouterBudgetViewModel
    ) {
        self.runtimes = [
            .claude: claude,
            .codex: codex,
            .grok: grok,
            .openrouter: openRouter
        ]
        startMemoryPressureObservation()
    }

    init(runtimes: [any ProviderRuntime], observeMemoryPressure: Bool = true) {
        self.runtimes = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.providerID, $0) })
        if observeMemoryPressure {
            startMemoryPressureObservation()
        }
    }

    var isActive: (ProviderID) -> Bool {
        { [weak self] provider in self?.activeProviders.contains(provider) ?? false }
    }

    /// Resumes every enabled provider in stable order, each in its own task, and keeps
    /// following the enablement store from then on. Safe to call once; later calls no-op.
    func start(observing providers: EnabledProviders) {
        guard !hasStarted else { return }
        hasStarted = true
        AppRuntimeState.recordBreadcrumb("coordinator-start")

        for provider in ProviderID.allCases where providers.isEnabled(provider) {
            schedule(provider, enabled: true)
        }

        let stream = providers.changes()
        enablementTask = Task { [weak self] in
            for await change in stream {
                guard !Task.isCancelled else { return }
                self?.schedule(change.provider, enabled: change.isEnabled)
            }
        }
    }

    func apply(_ provider: ProviderID, enabled: Bool) async {
        if enabled {
            await resume(provider)
        } else {
            await suspend(provider)
        }
    }

    func resume(_ provider: ProviderID) async {
        guard !activeProviders.contains(provider), let runtime = runtimes[provider] else { return }
        AppRuntimeState.recordBreadcrumb("provider-\(provider.rawValue)-enabled")
        await runtime.enable()
        activeProviders.insert(provider)
    }

    func suspend(_ provider: ProviderID) async {
        guard activeProviders.contains(provider), let runtime = runtimes[provider] else { return }
        AppRuntimeState.recordBreadcrumb("provider-\(provider.rawValue)-disabled")
        await runtime.disable()
        activeProviders.remove(provider)
    }

    func refresh(_ provider: ProviderID) async {
        guard activeProviders.contains(provider) else { return }
        await runtimes[provider]?.refresh()
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) async {
        let active = ProviderID.allCases.filter { activeProviders.contains($0) }
        await withTaskGroup(of: Void.self) { group in
            for provider in active {
                guard let runtime = runtimes[provider] else { continue }
                group.addTask { @MainActor in
                    await runtime.handleMemoryPressure(level)
                }
            }
        }
    }

    /// Termination: stop every active provider, then let the delegate mark the exit.
    func stopAll() async {
        enablementTask?.cancel()
        enablementTask = nil
        for task in transitions.values {
            task.cancel()
        }
        transitions.removeAll()
        for provider in ProviderID.allCases where activeProviders.contains(provider) {
            await suspend(provider)
        }
    }

    // MARK: - Private

    /// Queues the transition behind any transition already running for that provider.
    private func schedule(_ provider: ProviderID, enabled: Bool) {
        let previous = transitions[provider]
        let task = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.apply(provider, enabled: enabled)
        }
        transitions[provider] = task
    }

    private func startMemoryPressureObservation() {
        memoryPressureTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .planTrackerMemoryPressure
            )
            for await notification in notifications {
                guard !Task.isCancelled else { return }
                guard let self, let level = notification.object as? AppMemoryPressureLevel else { continue }
                await self.handleMemoryPressure(level)
            }
        }
    }
}
