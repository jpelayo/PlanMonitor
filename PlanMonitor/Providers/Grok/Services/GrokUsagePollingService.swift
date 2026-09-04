import Foundation

actor GrokUsagePollingService {
    private let apiClient: GrokAPIClient
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 300
    private var intervalGeneration = 0
    private var onUsageUpdate: (@Sendable (GrokUsageData) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?
    private var onSchedule: (@Sendable (Date?) -> Void)?
    private var prepare: (@Sendable (Bool) async throws -> Void)?
    /// Plan metadata changes rarely; refetch it on this cadence, stretched under memory pressure.
    private var metadataRefreshInterval: TimeInterval = 6 * 3600
    private var lastMetadataRefreshAt: Date?
    /// The billing payload never carries the tier, so the last fetched name is reapplied to every
    /// usage update in between metadata refreshes; otherwise the badge would vanish on the first
    /// poll after each refresh and stay hidden for hours.
    private var lastPlanDisplayName: String?
    private var nextFireAt: Date? {
        didSet { onSchedule?(nextFireAt) }
    }

    init(apiClient: GrokAPIClient) {
        self.apiClient = apiClient
    }

    func setCallbacks(
        onUsageUpdate: @escaping @Sendable (GrokUsageData) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        prepare: (@Sendable (Bool) async throws -> Void)? = nil,
        onSchedule: (@Sendable (Date?) -> Void)? = nil
    ) {
        self.onUsageUpdate = onUsageUpdate
        self.onError = onError
        self.prepare = prepare
        self.onSchedule = onSchedule
    }

    /// Applies at once by interrupting the pending sleep; never forces a fetch.
    func setPollingInterval(_ interval: TimeInterval) {
        let clamped = max(60, interval)
        guard clamped != pollingInterval else { return }
        pollingInterval = clamped
        intervalGeneration &+= 1
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchUsage()
                await self.sleepUntilNextCycle()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        nextFireAt = nil
    }

    func resetSteadyState() {
        lastMetadataRefreshAt = nil
        lastPlanDisplayName = nil
        metadataRefreshInterval = 6 * 3600
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) {
        switch level {
        case .warning:
            metadataRefreshInterval = max(metadataRefreshInterval, 12 * 3600)
        case .critical:
            metadataRefreshInterval = max(metadataRefreshInterval, 24 * 3600)
        }
    }

    func fetchUsage(forceMetadataRefresh: Bool = false) async {
        do {
            try await loadUsage(forceMetadataRefresh: forceMetadataRefresh, forceRefresh: false)
        } catch GrokAPIError.unauthorized, GrokAPIError.noAccessToken {
            do {
                try await loadUsage(forceMetadataRefresh: forceMetadataRefresh, forceRefresh: true)
            } catch {
                onError?(error)
            }
        } catch {
            onError?(error)
        }
    }

    private func loadUsage(forceMetadataRefresh: Bool, forceRefresh: Bool) async throws {
        if let prepare {
            try await prepare(forceRefresh)
        }
        var usage = try await apiClient.fetchWeeklyUsage()
        let metadataIsStale = lastMetadataRefreshAt.map {
            Date().timeIntervalSince($0) >= metadataRefreshInterval
        } ?? true
        if forceMetadataRefresh || metadataIsStale,
           let plan = try? await apiClient.fetchPlanDisplayName() {
            lastPlanDisplayName = plan
            lastMetadataRefreshAt = Date()
        }
        usage.planDisplayName = lastPlanDisplayName
        onUsageUpdate?(usage)
    }

    private func sleepUntilNextCycle() async {
        let start = Date()
        var generation = intervalGeneration
        var deadline = start.addingTimeInterval(pollingInterval)
        nextFireAt = deadline
        defer { nextFireAt = nil }
        while !Task.isCancelled {
            if intervalGeneration != generation {
                generation = intervalGeneration
                deadline = start.addingTimeInterval(pollingInterval)
                nextFireAt = deadline
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return }
            try? await Task.sleep(for: .seconds(min(remaining, 1.0)))
        }
    }
}
