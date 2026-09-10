import Foundation

nonisolated struct PollOutcome: Sendable {
    var snapshot: OpenRouterSnapshot
    /// Non-fatal problems from a partially successful cycle. The snapshot is still good.
    var degradedReason: String?
}

/// Owns the refresh loop and the per-resource caches.
///
/// Two defects from the donor variants are deliberately not inherited:
///  1. Grok restarts the whole cycle on an interval change, forcing a needless fetch;
///     Claude only assigns, so the change waits out the current sleep. Here the sleep
///     itself is interruptible, so a new interval applies at once with no extra call.
///  2. Neither donor has any backoff. This one does.
actor OpenRouterBudgetPollingService {
    private let apiClient: OpenRouterAPIClient

    private var pollingTask: Task<Void, Never>?
    private var interval: TimeInterval = 300
    private var inFlight = false

    // Slow-moving configuration is cached; fast-moving money is not. Cuts the steady
    // state from four calls to two.
    private var cachedGuardrails: [GuardrailDTO]?
    private var cachedAssignments: [GuardrailKeyAssignmentDTO]?
    private var guardrailsRefreshedAt: Date?
    private var guardrailRefreshInterval: TimeInterval = 6 * 3600
    private var guardrailsUnavailable = false
    // /activity only ever changes at UTC midnight, so it belongs on the slow tier.
    private var cachedActivity: [ActivityRowDTO]?
    /// Whether the caller wants the recent-models section; skips the analytics call
    /// entirely when the section is off and the trailing spend lines are all that's
    /// needed — the same query serves both, so this only gates nothing extra today.
    private var recentModelsWindow: RecentModelsWindow = .fifteenMinutes
    // Last successful cycle's model feeds and the outcome built from them. Both feeds are fetched
    // every cycle whatever the window is, so a window change can be answered from these instead of
    // waiting out the interval — which is what made the recent-models list look frozen.
    private var cachedAnalytics: [AnalyticsRowDTO]?
    private var cachedDayAnalytics: [AnalyticsRowDTO]?
    private var lastOutcome: PollOutcome?

    private var consecutiveFailures = 0
    private var cycleGeneration = 0
    private var onUpdate: (@Sendable (PollOutcome) -> Void)?
    private var onError: (@Sendable (OpenRouterAPIError) -> Void)?
    private var onSchedule: (@Sendable (Date?) -> Void)?
    private var nextFireAt: Date? {
        didSet { onSchedule?(nextFireAt) }
    }

    init(apiClient: OpenRouterAPIClient) {
        self.apiClient = apiClient
    }

    func setCallbacks(
        onUpdate: @escaping @Sendable (PollOutcome) -> Void,
        onError: @escaping @Sendable (OpenRouterAPIError) -> Void,
        onSchedule: (@Sendable (Date?) -> Void)? = nil
    ) {
        self.onUpdate = onUpdate
        self.onError = onError
        self.onSchedule = onSchedule
    }

    /// Applies at once, without a fetch: both analytics feeds are already in hand, so the new
    /// window is re-assembled from them and republished immediately.
    func setRecentModelsWindow(_ window: RecentModelsWindow) {
        guard window != recentModelsWindow else { return }
        recentModelsWindow = window
        guard var outcome = lastOutcome else { return }
        outcome.snapshot.recentModels = OpenRouterBudgetAssembler.recentModels(
            analytics: cachedAnalytics,
            dayAnalytics: cachedDayAnalytics,
            window: window
        )
        lastOutcome = outcome
        onUpdate?(outcome)
    }

    func setInterval(_ newValue: TimeInterval) {
        let clamped = max(180, newValue)
        guard clamped != interval else { return }
        interval = clamped
        // Touching the setting means "try again on the new schedule": a pending backoff is
        // dropped rather than scaled, so the countdown restarts at the plain new interval.
        consecutiveFailures = 0
        cycleGeneration &+= 1        // interrupts the pending sleep, no fetch
    }

    /// Restarts the pending cycle from now without fetching. The manual Refresh button has
    /// just done this cycle's work out of band, so the next automatic poll — and the
    /// countdown built from its deadline — should be a full delay away.
    func restartCycle() {
        cycleGeneration &+= 1
    }

    func start() {
        stop()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.poll(force: false)
                await self.sleepUntilNextCycle()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        nextFireAt = nil
    }

    /// Clears caches and failure state. Called on disconnect.
    func resetSteadyState() {
        cachedGuardrails = nil
        cachedAssignments = nil
        cachedActivity = nil
        cachedAnalytics = nil
        cachedDayAnalytics = nil
        lastOutcome = nil
        guardrailsRefreshedAt = nil
        guardrailRefreshInterval = 6 * 3600
        guardrailsUnavailable = false
        consecutiveFailures = 0
    }

    /// Stretch TTLs rather than dropping caches — discarding only forces a refetch.
    func handleMemoryPressure(_ level: AppMemoryPressureLevel) {
        switch level {
        case .warning:
            guardrailRefreshInterval = max(guardrailRefreshInterval, 12 * 3600)
        case .critical:
            guardrailRefreshInterval = max(guardrailRefreshInterval, 24 * 3600)
        }
    }

    func refreshNow() async {
        await poll(force: true)
        // `poll` has already updated `consecutiveFailures`, so re-anchoring now recomputes a
        // plain interval after a success and a fresh backoff after a failure.
        restartCycle()
    }

    // MARK: - Cycle

    private func poll(force: Bool) async {
        guard !inFlight else { return }          // dedupe manual against scheduled
        inFlight = true
        defer { inFlight = false }

        let needsGuardrails = force || shouldRefreshGuardrails

        // Concurrent, but each result is optional: one endpoint failing must not blank
        // the others.
        async let creditsResult = attempt { try await self.apiClient.fetchCredits() }
        async let keysResult = attempt { try await self.apiClient.fetchKeys() }
        // Trailing-window spend moves minute to minute, so it is fetched every cycle.
        async let analyticsResult = attempt { try await self.apiClient.queryRecentUsage(minutes: 60) }
        async let dayAnalyticsResult = attempt { try await self.apiClient.queryLast24Hours() }

        let credits = await creditsResult
        let keys = await keysResult
        let analytics = try? await analyticsResult.get()
        let dayAnalytics = try? await dayAnalyticsResult.get()

        var guardrails = cachedGuardrails ?? []
        var assignments = cachedAssignments ?? []
        var degraded: [String] = []

        if needsGuardrails {
            if case .success(let rows) = await attempt({ try await self.apiClient.fetchActivity() }) {
                cachedActivity = rows
            } else if cachedActivity == nil {
                degraded.append(String(localized: "30-day spend is unavailable."))
            }
        }

        if needsGuardrails && !guardrailsUnavailable {
            async let gResult = attempt { try await self.apiClient.fetchGuardrails() }
            async let aResult = attempt { try await self.apiClient.fetchGuardrailKeyAssignments() }
            let g = await gResult
            let a = await aResult

            switch (g, a) {
            case (.success(let gv), .success(let av)):
                guardrails = gv
                assignments = av
                cachedGuardrails = gv
                cachedAssignments = av
                guardrailsRefreshedAt = Date()
            case (.failure(OpenRouterAPIError.guardrailsUnavailable), _),
                 (_, .failure(OpenRouterAPIError.guardrailsUnavailable)):
                // Personal account: the section is absent, not broken.
                guardrailsUnavailable = true
                guardrails = []
                assignments = []
            default:
                // Keep whatever was cached; stale beats nothing.
                degraded.append(String(localized: "Guardrails could not be refreshed."))
            }
        }

        // A definitive credential failure is worth surfacing even if other calls worked.
        if case .failure(let error) = credits, !error.isTransient {
            onError?(error)
            if error == .unauthorized || error == .notAManagementKey { return }
        }

        let creditsValue = try? credits.get()
        let keysValue = (try? keys.get()) ?? []

        if case .failure(let error) = keys {
            if !error.isTransient { onError?(error) }
            degraded.append(String(localized: "Key limits could not be refreshed."))
        }
        if case .failure(let error) = credits, error.isTransient {
            degraded.append(String(localized: "Credit balance could not be refreshed."))
        }

        // Nothing at all came back — treat as a failed cycle and back off.
        if creditsValue == nil && keysValue.isEmpty {
            consecutiveFailures += 1
            if case .failure(let error) = credits { onError?(error) }
            return
        }

        consecutiveFailures = 0
        let snapshot = OpenRouterBudgetAssembler.assemble(
            credits: creditsValue,
            keys: keysValue,
            guardrails: guardrails,
            assignments: assignments,
            activity: cachedActivity,
            analytics: analytics,
            dayAnalytics: dayAnalytics,
            recentModelsWindow: recentModelsWindow,
            guardrailsAvailable: !guardrailsUnavailable,
            now: Date()
        )
        let outcome = PollOutcome(
            snapshot: snapshot,
            degradedReason: degraded.isEmpty ? nil : degraded.joined(separator: " ")
        )
        cachedAnalytics = analytics
        cachedDayAnalytics = dayAnalytics
        lastOutcome = outcome
        onUpdate?(outcome)
    }

    private var shouldRefreshGuardrails: Bool {
        guard let refreshedAt = guardrailsRefreshedAt else { return true }
        return Date().timeIntervalSince(refreshedAt) >= guardrailRefreshInterval
    }

    private func attempt<T: Sendable>(
        _ work: @Sendable @escaping () async throws -> T
    ) async -> Result<T, OpenRouterAPIError> {
        do {
            return .success(try await work())
        } catch let error as OpenRouterAPIError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - Interruptible sleep

    /// Sleeps in short slices so an interval change takes effect at once without
    /// forcing a fetch. One-second granularity is free at a 3–60 minute cadence.
    private func sleepUntilNextCycle() async {
        var generation = cycleGeneration
        var deadline = nextDeadline()
        nextFireAt = deadline
        defer { nextFireAt = nil }
        while !Task.isCancelled {
            if cycleGeneration != generation {
                // Interval change or manual refresh: restart the cycle from now, no fetch.
                // Both the anchor and the backoff are recomputed — anchoring on the cycle's
                // original start would leave the countdown short, and replaying the delay
                // captured on entry would keep counting down a backoff already cleared.
                generation = cycleGeneration
                deadline = nextDeadline()
                nextFireAt = deadline
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return }
            let slice = min(remaining, 1.0)
            try? await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
        }
    }

    /// How far out the next poll sits: the plain interval, or a backoff while cycles are
    /// failing. Read afresh at every anchor point, so a cleared failure count takes effect.
    private func nextDeadline(from now: Date = Date()) -> Date {
        now.addingTimeInterval(backoffDelay ?? interval)
    }

    /// Exponential backoff with jitter. 429 is treated as a strong signal because the
    /// management-endpoint rate limit is undocumented.
    private var backoffDelay: TimeInterval? {
        guard consecutiveFailures > 0 else { return nil }
        let exponent = min(consecutiveFailures, 6)
        let base = min(interval * pow(2, Double(exponent)), 3600)
        let jitter = Double.random(in: 0.85...1.15)
        return base * jitter
    }
}
