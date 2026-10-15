import Foundation

/// Polls the console's billing for one org. Credit and spend move with every request the account
/// makes, so they are read each cycle; the limits and auto-payment change rarely and
/// ride a slower metadata cadence, which memory pressure stretches rather than clears.
///
/// The cycle mechanics — interruptible one-second sleeps, a real published `nextFireAt`, an
/// interval change or manual refresh restarting the cycle without fetching — are the house shape
/// shared with Claude and Codex. No backoff: OpenRouter is the only provider with one.
actor ClaudePlatformPollingService {
    private static let defaultMetadataRefreshInterval: TimeInterval = 3600

    private let apiClient: ClaudePlatformClient
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 300
    private var organizationID: String?

    private var cachedLimits: ClaudePlatformSpendLimitsResponse?
    private var cachedAutoRecharge: ClaudePlatformAutoRechargeResponse?
    private var lastMetadataRefreshAt: Date?
    private var metadataRefreshInterval: TimeInterval = defaultMetadataRefreshInterval

    private var onUpdate: (@Sendable (ClaudePlatformSnapshot) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?
    private var onSchedule: (@Sendable (Date?) -> Void)?
    private var cycleGeneration = 0
    private var nextFireAt: Date? {
        didSet { onSchedule?(nextFireAt) }
    }

    init(apiClient: ClaudePlatformClient) {
        self.apiClient = apiClient
    }

    func setCallbacks(
        onUpdate: @escaping @Sendable (ClaudePlatformSnapshot) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        onSchedule: (@Sendable (Date?) -> Void)? = nil
    ) {
        self.onUpdate = onUpdate
        self.onError = onError
        self.onSchedule = onSchedule
    }

    /// A different org invalidates everything cached for the old one.
    func setOrganizationID(_ id: String?) {
        guard id != organizationID else { return }
        organizationID = id
        clearMetadata()
    }

    /// Applies at once by interrupting the pending sleep; never forces a fetch. The pending
    /// cycle restarts from now, so the published deadline is always a full interval out.
    func setPollingInterval(_ interval: TimeInterval) {
        let clamped = Swift.max(60, interval)
        guard clamped != pollingInterval else { return }
        pollingInterval = clamped
        cycleGeneration &+= 1
    }

    /// Restarts the pending cycle from now without fetching. The manual Refresh button has
    /// just done this cycle's work out of band, so the next automatic poll — and the
    /// countdown built from its deadline — should be a full interval away.
    func restartCycle() {
        cycleGeneration &+= 1
    }

    func startPolling() {
        stopPolling()

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchSnapshot()
                await self.sleepUntilNextCycle()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        nextFireAt = nil
    }

    /// Sleeps in one-second slices so an interval change reschedules immediately and the
    /// published deadline is the real one.
    private func sleepUntilNextCycle() async {
        var generation = cycleGeneration
        var deadline = Date().addingTimeInterval(pollingInterval)
        nextFireAt = deadline
        defer { nextFireAt = nil }
        while !Task.isCancelled {
            if cycleGeneration != generation {
                // Interval change or manual refresh: restart the cycle from now, no fetch.
                generation = cycleGeneration
                deadline = Date().addingTimeInterval(pollingInterval)
                nextFireAt = deadline
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return }
            try? await Task.sleep(for: .seconds(min(remaining, 1.0)))
        }
    }

    func resetSteadyState() {
        organizationID = nil
        clearMetadata()
        metadataRefreshInterval = Self.defaultMetadataRefreshInterval
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) {
        switch level {
        case .warning:
            metadataRefreshInterval = max(metadataRefreshInterval, 2 * 3600)
        case .critical:
            metadataRefreshInterval = max(metadataRefreshInterval, 6 * 3600)
        }
    }

    func fetchSnapshot(forceMetadataRefresh: Bool = false) async {
        do {
            let snapshot = try await fetch(forceMetadataRefresh: forceMetadataRefresh)
            ClaudePlatformDiagnostics.log(ClaudePlatformDiagnostics.describe(snapshot))
            onUpdate?(snapshot)
        } catch {
            ClaudePlatformDiagnostics.log("poll failed: \(error.localizedDescription)")
            onError?(error)
        }
    }

    private func fetch(forceMetadataRefresh: Bool) async throws -> ClaudePlatformSnapshot {
        guard let organizationID else {
            throw ClaudePlatformClient.APIError.organizationUnavailable
        }

        async let creditsTask = apiClient.fetchPrepaidCredits(organizationID: organizationID)
        async let spendTask = apiClient.fetchCurrentSpend(organizationID: organizationID)

        if forceMetadataRefresh || metadataIsStale() {
            await refreshMetadata(organizationID: organizationID)
        }

        let credits = try await creditsTask
        let spend = try await spendTask

        return ClaudePlatformBilling.assemble(
            credits: credits,
            spend: spend,
            limits: cachedLimits,
            autoRecharge: cachedAutoRecharge
        )
    }

    /// Failures keep what is cached: a missing denominator degrades one row, never the poll. The
    /// cadence restarts only once the limits — the spend gauge's denominator — have been read.
    private func refreshMetadata(organizationID: String) async {
        async let limitsTask = try? apiClient.fetchSpendLimits(organizationID: organizationID)
        async let autoRechargeTask = try? apiClient.fetchAutoRecharge(organizationID: organizationID)

        let limits = await limitsTask
        let autoRecharge = await autoRechargeTask
        ClaudePlatformDiagnostics.log(
            "metadata refresh: spend_limits \(limits == nil ? "FAILED" : "ok"), "
                + "auto_recharge \(autoRecharge == nil ? "FAILED" : "ok")"
        )
        if let autoRecharge {
            cachedAutoRecharge = autoRecharge
        }
        if let limits {
            cachedLimits = limits
            lastMetadataRefreshAt = Date()
        }
    }

    private func metadataIsStale() -> Bool {
        guard let lastMetadataRefreshAt else { return true }
        return Date().timeIntervalSince(lastMetadataRefreshAt) >= metadataRefreshInterval
    }

    private func clearMetadata() {
        cachedLimits = nil
        cachedAutoRecharge = nil
        lastMetadataRefreshAt = nil
    }
}
