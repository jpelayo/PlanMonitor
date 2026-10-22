import Foundation

/// Owns the refresh loop: each cycle reads the Go windows and the member budgets concurrently.
///
/// `OpenRouterBudgetPollingService`'s shape without its caches — both figures move every cycle, so
/// nothing is slow enough to cache: an interruptible sleep, so an interval change applies at once
/// with no fetch; a published deadline for the footer countdown; and exponential backoff with
/// jitter while cycles fail. A cycle that reads either half counts as a success
/// (`OpenCodePollOutcome.make`).
actor OpenCodePollingService {
    private let apiClient: OpenCodeAPIClient

    private var pollingTask: Task<Void, Never>?
    private var interval: TimeInterval = 300
    private var inFlight = false
    private var consecutiveFailures = 0
    private var cycleGeneration = 0
    private var onUpdate: (@Sendable (OpenCodePollOutcome) -> Void)?
    private var onError: (@Sendable (OpenCodeAPIError) -> Void)?
    private var onSchedule: (@Sendable (Date?) -> Void)?
    private var nextFireAt: Date? {
        didSet { onSchedule?(nextFireAt) }
    }

    init(apiClient: OpenCodeAPIClient) {
        self.apiClient = apiClient
    }

    func setCallbacks(
        onUpdate: @escaping @Sendable (OpenCodePollOutcome) -> Void,
        onError: @escaping @Sendable (OpenCodeAPIError) -> Void,
        onSchedule: (@Sendable (Date?) -> Void)? = nil
    ) {
        self.onUpdate = onUpdate
        self.onError = onError
        self.onSchedule = onSchedule
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

    /// Restarts the pending cycle from now without fetching.
    func restartCycle() {
        cycleGeneration &+= 1
    }

    func start() {
        stop()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.poll()
                await self.sleepUntilNextCycle()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        nextFireAt = nil
    }

    /// Clears the failure state. Called on disconnect and on a new key.
    func resetSteadyState() {
        consecutiveFailures = 0
    }

    /// The manual Refresh: fetch now, then owe the automatic poll a full delay.
    func refreshNow() async {
        await poll()
        restartCycle()
    }

    // MARK: - Cycle

    private func poll() async {
        guard !inFlight else { return }          // dedupe manual against scheduled
        inFlight = true
        defer { inFlight = false }

        // Concurrent, and each result separate: one endpoint failing must not blank the other.
        async let membersResult = attempt { try await self.apiClient.fetchMemberBudgets().map(\.member) }
        async let goResult = attempt { try await self.apiClient.fetchGoUsage() }

        switch OpenCodePollOutcome.make(members: await membersResult, go: await goResult, fetchedAt: Date()) {
        case .success(let outcome):
            consecutiveFailures = 0
            onUpdate?(outcome)
        case .failure(let error):
            if error.isTransient {
                consecutiveFailures += 1
            }
            onError?(error)
        }
    }

    private func attempt<T: Sendable>(
        _ work: @Sendable @escaping () async throws -> T
    ) async -> Result<T, OpenCodeAPIError> {
        do {
            return .success(try await work())
        } catch let error as OpenCodeAPIError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - Interruptible sleep

    /// Sleeps in one-second slices so an interval change or a manual refresh re-anchors the
    /// deadline at once, without forcing a fetch.
    private func sleepUntilNextCycle() async {
        var generation = cycleGeneration
        var deadline = nextDeadline()
        nextFireAt = deadline
        defer { nextFireAt = nil }
        while !Task.isCancelled {
            if cycleGeneration != generation {
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

    private func nextDeadline(from now: Date = Date()) -> Date {
        now.addingTimeInterval(backoffDelay ?? interval)
    }

    /// Exponential backoff with jitter, capped at an hour. The API's rate limit is undocumented.
    private var backoffDelay: TimeInterval? {
        guard consecutiveFailures > 0 else { return nil }
        let exponent = min(consecutiveFailures, 6)
        let base = min(interval * pow(2, Double(exponent)), 3600)
        return base * Double.random(in: 0.85...1.15)
    }
}
