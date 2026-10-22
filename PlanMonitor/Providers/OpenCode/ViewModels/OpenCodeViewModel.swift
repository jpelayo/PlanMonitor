import Foundation
import SwiftUI

/// OpenCode: the Go subscription's 5-hour, weekly and monthly windows, and this month's Console
/// spend against the member's budget, both read with one Console API key.
///
/// The key lifecycle is OpenRouter's — pasted into a Connect window, validated by the API before it
/// is stored, a 401 marking it invalid without deleting anything. The Go half is Grok's shape
/// (window cards, the global remaining/used switch on the bar, the status pill), the money half
/// Claude-API's conventions. The credit balance is pending: `console/api/billing/status` refuses
/// every key, and only a signed-in console session reads it (OpenCode issue #10448).
@MainActor
@Observable
final class OpenCodeViewModel {
    private(set) var connectionState: OpenCodeConnectionState = .disconnected
    private(set) var snapshot: OpenCodeSnapshot = .empty
    /// The last poll's rows, for the Settings member picker. In memory only: other members'
    /// addresses are never written to disk.
    private(set) var members: [OpenCodeMemberBudget] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isDemoMode = false
    private(set) var nextRefreshAt: Date?
    private(set) var systemStatus: OpenCodeSystemStatus = .degraded
    private(set) var statusFetchedAt: Date?

    var connectError: String?

    var pollingIntervalMinutes: Int = 5 {
        didSet {
            let seconds = TimeInterval(pollingIntervalMinutes * 60)
            Task { await pollingService.setInterval(seconds) }
        }
    }

    var menuBarDisplay: OpenCodeMenuBarDisplay = .default {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: "opencode.menuBarDisplay") }
    }

    /// What fills the ring around the menu-bar glyph.
    var ringSource: OpenCodeRingSource = .off {
        didSet { defaults.set(ringSource.rawValue, forKey: "opencode.ringSource") }
    }

    /// How amounts carry their currency, in the menu bar and the dropdown alike.
    var currencyStyle: CurrencyStyle = .default {
        didSet { defaults.set(currencyStyle.rawValue, forKey: "opencode.currencyStyle") }
    }

    /// Whose budget to show when the workspace has several members. `nil` shows the workspace's
    /// summed spend. Re-assembles the snapshot from the last poll, without a fetch.
    var memberID: String? {
        didSet {
            defaults.set(memberID, forKey: "opencode.memberID")
            guard !isDemoMode, !members.isEmpty, let fetchedAt = snapshot.fetchedAt else { return }
            snapshot = OpenCodeSnapshot.merging(
                previous: snapshot,
                members: .read(members),
                go: .unchanged,
                selectedMemberID: memberID,
                fetchedAt: fetchedAt
            )
            persistSnapshot()
        }
    }

    /// `MenuBarLabel.variableValue`: `nil` leaves the ring whole.
    var ringFill: Double? {
        guard connectionState.showsBudget else { return nil }
        return ringSource.fill(for: snapshot)
    }

    /// Shown in orange above the footer: what is on screen is right, but not the whole story.
    var degradedMessage: String? {
        guard connectionState.showsBudget, snapshot.isWorkspaceTotal else { return nil }
        return String(localized: "Several members share this workspace. Choose yours in Settings to see your budget.")
    }

    /// Three missed cycles in a row.
    var isStale: Bool {
        guard let lastUpdated, !isDemoMode else { return false }
        if case .invalidKey = connectionState { return true }
        return Date().timeIntervalSince(lastUpdated) > TimeInterval(pollingIntervalMinutes * 60 * 3)
    }

    /// The member's address once a poll has named one, else the key's public prefix.
    var identityLabel: String? {
        snapshot.memberEmail ?? connectionState.keyPrefix
    }

    let sessionPreferences: SessionTrackingPreferences
    let sessionTracker: SessionTracker
    let menuBarText: MenuBarTextPreferences

    private let defaults: UserDefaults
    private let apiClient: OpenCodeAPIClient
    private let credentialStore: OpenCodeCredentialStore
    private let pollingService: OpenCodePollingService
    private let statusService: OpenCodeStatusService
    private let snapshotStore: OpenCodeSnapshotStore
    /// The client holds the stored key. False while the Keychain is locked, when the dropdown can
    /// show the cached snapshot as connected but there is nothing to poll with yet.
    private var hasCredential = false
    private var credentialRetryTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private let credentialRetryDelay: TimeInterval = 60
    private let statusRefreshInterval: TimeInterval = 5 * 60
    private var isFetchingStatus = false

    init(
        secureStore: any SecureStore,
        defaults: UserDefaults = .standard,
        apiClient: OpenCodeAPIClient = OpenCodeAPIClient()
    ) {
        self.defaults = defaults
        self.apiClient = apiClient
        self.credentialStore = OpenCodeCredentialStore(secureStore: secureStore)
        self.pollingService = OpenCodePollingService(apiClient: apiClient)
        self.statusService = OpenCodeStatusService()
        self.snapshotStore = OpenCodeSnapshotStore(defaults: defaults)
        self.sessionPreferences = SessionTrackingPreferences(namespace: "opencode", defaults: defaults)
        self.sessionTracker = SessionTracker(namespace: "opencode", defaults: defaults)
        self.menuBarText = MenuBarTextPreferences(namespace: "opencode", defaults: defaults)

        // Direct assignment in `init` does not run `didSet`, so restored values are not written back.
        if let raw = defaults.string(forKey: "opencode.menuBarDisplay"),
           let display = OpenCodeMenuBarDisplay(rawValue: raw) {
            menuBarDisplay = display
        }
        if let raw = defaults.string(forKey: "opencode.ringSource"),
           let source = OpenCodeRingSource(rawValue: raw) {
            ringSource = source
        }
        if let raw = defaults.string(forKey: "opencode.currencyStyle"),
           let style = CurrencyStyle(rawValue: raw) {
            currencyStyle = style
        }
        memberID = defaults.string(forKey: "opencode.memberID")

        setupCallbacks()
    }

    // MARK: - Lifecycle

    /// Restores the stored key and starts polling; the first poll is the validation. A locked
    /// Keychain is transient — the cached snapshot stays, a retry is scheduled, nothing is deleted.
    func start() async {
        guard !isDemoMode else { return }
        connectionState = .validating
        AppRuntimeState.recordBreadcrumb("provider-opencode-check-credential")

        let stored: OpenCodeAPIKey?
        do {
            stored = try await credentialStore.load()
        } catch {
            AppRuntimeState.recordBreadcrumb("provider-opencode-keychain-unavailable")
            restorePersistedSnapshot()
            connectionState = snapshot.isEmpty ? .disconnected : .connected(keyPrefix: String(localized: "OpenCode key"))
            errorMessage = String(localized: "Keychain is locked. Retrying shortly.")
            scheduleCredentialRetry()
            return
        }

        guard let stored, let prefix = stored.prefix else {
            AppRuntimeState.recordBreadcrumb("provider-opencode-credential-missing")
            connectionState = .disconnected
            snapshotStore.clear()
            return
        }

        AppRuntimeState.recordBreadcrumb("provider-opencode-credential-restored")
        restorePersistedSnapshot()
        await apiClient.setCredential(stored.key)
        hasCredential = true
        connectionState = .connected(keyPrefix: prefix)
        errorMessage = nil
        await startPolling()
    }

    private func scheduleCredentialRetry() {
        credentialRetryTask?.cancel()
        credentialRetryTask = Task { [weak self, credentialRetryDelay] in
            try? await Task.sleep(for: .seconds(credentialRetryDelay))
            guard !Task.isCancelled else { return }
            await self?.start()
        }
    }

    /// Validates and stores a pasted key. Returns true when the connection succeeded. The key is
    /// written only after the API answered for it — with Go usage, budgets, or both.
    func connect(with rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        connectError = nil

        guard OpenCodeAPIKey.looksValid(key), let prefix = OpenCodeAPIKey.prefix(of: key) else {
            connectError = String(localized: "That does not look like an OpenCode API key.")
            return false
        }

        isLoading = true
        let previousState = connectionState
        connectionState = .validating
        defer { isLoading = false }

        let client = apiClient
        async let membersResult = Self.attempt { try await client.fetchMemberBudgets(credential: key).map(\.member) }
        async let goResult = Self.attempt { try await client.fetchGoUsage(credential: key) }
        let outcome: OpenCodePollOutcome
        switch OpenCodePollOutcome.make(members: await membersResult, go: await goResult, fetchedAt: Date()) {
        case .success(let value):
            outcome = value
        case .failure(let error):
            connectError = error.errorDescription
            connectionState = previousState.showsBudget ? previousState : .disconnected
            return false
        }

        do {
            try await credentialStore.save(OpenCodeAPIKey(key: key))
        } catch {
            connectError = error.localizedDescription
            connectionState = previousState.showsBudget ? previousState : .disconnected
            return false
        }
        await apiClient.setCredential(key)
        hasCredential = true
        isDemoMode = false
        connectionState = .connected(keyPrefix: prefix)
        errorMessage = nil
        AppRuntimeState.recordBreadcrumb("provider-opencode-connected")
        // A new key may belong to another workspace: nothing from the previous one carries over.
        snapshot = .empty
        apply(outcome)
        await pollingService.resetSteadyState()
        await startPolling()
        return true
    }

    nonisolated private static func attempt<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, OpenCodeAPIError> {
        do {
            return .success(try await work())
        } catch let error as OpenCodeAPIError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    func refreshUsage() async {
        guard connectionState.showsBudget, !isDemoMode, !isLoading else { return }
        AppRuntimeState.recordBreadcrumb("provider-opencode-manual-refresh")
        isLoading = true
        await pollingService.refreshNow()
        await refreshStatus(force: true)
        isLoading = false
    }

    func suspend() async {
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        statusTask?.cancel()
        statusTask = nil
        await pollingService.stop()
        nextRefreshAt = nil
    }

    func resume() async {
        guard !isDemoMode else { return }
        if hasCredential, case .connected = connectionState {
            await startPolling()
        } else {
            await start()
        }
    }

    /// Deletes only PlanMonitor's copy of the key. It stays valid in the OpenCode Console.
    func disconnect() async {
        AppRuntimeState.recordBreadcrumb("provider-opencode-disconnect")
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        statusTask?.cancel()
        statusTask = nil
        await pollingService.stop()
        await pollingService.resetSteadyState()
        await credentialStore.clear()
        await apiClient.setCredential(nil)
        hasCredential = false
        connectionState = .disconnected
        snapshot = .empty
        members = []
        lastUpdated = nil
        errorMessage = nil
        isDemoMode = false
        nextRefreshAt = nil
        snapshotStore.clear()
        CacheJanitor.cleanupTransientCaches(reason: "opencode-disconnect")
    }

    private func startPolling() async {
        AppRuntimeState.recordBreadcrumb("provider-opencode-poll-start")
        await pollingService.setInterval(TimeInterval(pollingIntervalMinutes * 60))
        await pollingService.start()
        await refreshStatus(force: true)
    }

    var dailySessionFormatted: String? {
        guard sessionPreferences.isEnabled else { return nil }
        return SessionTimeFormatter.line(totalSeconds: sessionTracker.totalSeconds)
    }

    // MARK: - Wiring

    /// Captures `self` weakly in the outer task as well — the inner closures' `[weak self]` would
    /// otherwise sit inside an implicit strong capture.
    private func setupCallbacks() {
        Task { [weak self, pollingService] in
            guard self != nil else { return }
            await pollingService.setCallbacks(
                onUpdate: { [weak self] outcome in
                    Task { @MainActor [weak self] in
                        self?.apply(outcome)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.apply(error)
                    }
                },
                onSchedule: { [weak self] date in
                    Task { @MainActor [weak self] in
                        self?.nextRefreshAt = date
                    }
                }
            )
        }
    }

    private func apply(_ outcome: OpenCodePollOutcome) {
        guard !isDemoMode else { return }
        switch outcome.members {
        case .read(let rows): members = rows
        case .unreadable: members = []
        case .unchanged: break
        }
        snapshot = OpenCodeSnapshot.merging(
            previous: snapshot,
            members: outcome.members,
            go: outcome.go,
            selectedMemberID: memberID,
            fetchedAt: outcome.fetchedAt
        )
        lastUpdated = outcome.fetchedAt
        errorMessage = nil
        if sessionPreferences.isEnabled {
            sessionTracker.processTick(
                signals: Self.activitySignals(for: snapshot),
                minInterval: sessionPreferences.checkInterval,
                resetHour: sessionPreferences.resetHour
            )
        }
        persistSnapshot()
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            await self?.refreshStatus(force: false)
        }
    }

    /// Counters that only grow within their window — the Go percentages and this month's spend —
    /// never a remaining figure, so a reset reads as a drop rather than as activity.
    static func activitySignals(for snapshot: OpenCodeSnapshot) -> [ActivitySignal] {
        [
            ActivitySignal.percent("goRolling", snapshot.go?.rolling?.usedPercent),
            ActivitySignal.percent("goWeekly", snapshot.go?.weekly?.usedPercent),
            ActivitySignal.percent("goMonthly", snapshot.go?.monthly?.usedPercent),
            ActivitySignal.amount("spent", snapshot.spent)
        ].compactMap { $0 }
    }

    private func apply(_ error: OpenCodeAPIError) {
        guard !isDemoMode else { return }
        errorMessage = error.errorDescription
        guard !error.isTransient, let prefix = connectionState.keyPrefix else { return }
        // The key itself was refused: polling it again cannot succeed. Everything stays — the
        // snapshot, marked stale, and the key — until the user replaces or removes it.
        AppRuntimeState.recordBreadcrumb("provider-opencode-key-rejected")
        connectionState = .invalidKey(keyPrefix: prefix, reason: error.errorDescription ?? "")
        Task { [pollingService] in await pollingService.stop() }
        nextRefreshAt = nil
    }

    // MARK: - Status pill

    var displayedSystemStatus: OpenCodeSystemStatus {
        statusFetchedAt == nil ? .operational : systemStatus
    }

    private func refreshStatus(force: Bool) async {
        guard !isDemoMode else { return }
        if !force, let statusFetchedAt, Date().timeIntervalSince(statusFetchedAt) < statusRefreshInterval {
            return
        }
        guard !isFetchingStatus else { return }
        isFetchingStatus = true
        defer { isFetchingStatus = false }

        do {
            let status = try await statusService.fetchStatus()
            guard !Task.isCancelled else { return }
            systemStatus = status
            statusFetchedAt = Date()
        } catch {
            // Keep the previous status on transient failures.
        }
    }

    // MARK: - Snapshot persistence

    private func restorePersistedSnapshot() {
        guard let persisted = snapshotStore.load() else { return }
        snapshot = persisted.snapshot
        lastUpdated = persisted.lastUpdated
        AppRuntimeState.recordBreadcrumb("provider-opencode-snapshot-restored")
    }

    private func persistSnapshot() {
        guard !isDemoMode, let lastUpdated else { return }
        snapshotStore.save(snapshot: snapshot, lastUpdated: lastUpdated)
    }
}

// MARK: - Reviewer mode

extension OpenCodeViewModel: DemoCapable {
    func enterDemo() {
        guard !isDemoMode else { return }
        isDemoMode = true
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        statusTask?.cancel()
        statusTask = nil
        Task { [pollingService] in await pollingService.stop() }
        nextRefreshAt = nil

        let now = Date()
        connectionState = .connected(keyPrefix: OpenCodeDemoSnapshot.keyPrefix)
        snapshot = OpenCodeDemoSnapshot.snapshot(now: now)
        members = []
        lastUpdated = now
        errorMessage = nil
        systemStatus = .operational
        statusFetchedAt = now
        sessionTracker.setMockAccumulated(83 * 60) // 1h 23m
    }
}
