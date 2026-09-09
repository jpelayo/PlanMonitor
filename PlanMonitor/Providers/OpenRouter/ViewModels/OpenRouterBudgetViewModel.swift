import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class OpenRouterBudgetViewModel {
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var snapshot: OpenRouterSnapshot = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var degradedMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isStale = false
    private(set) var isDemoMode = false
    private(set) var nextRefreshAt: Date?

    var connectError: String?

    var pollingIntervalMinutes: Int = 5 {
        didSet {
            let seconds = TimeInterval(pollingIntervalMinutes * 60)
            Task { await pollingService.setInterval(seconds) }
        }
    }

    var menuBarDisplay: MenuBarDisplay = .amount {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: "openrouter.menuBarDisplay") }
    }

    var showDisabledKeys: Bool = false {
        didSet { defaults.set(showDisabledKeys, forKey: "openrouter.showDisabledKeys") }
    }

    /// Persisted so the popover opens the way the user left it.
    var spendBreakdownExpanded: Bool = false {
        didSet { defaults.set(spendBreakdownExpanded, forKey: "openrouter.spendBreakdownExpanded") }
    }

    /// Adds a section listing the models called recently.
    var showRecentModels: Bool = false {
        didSet { defaults.set(showRecentModels, forKey: "openrouter.showRecentModels") }
    }

    /// How far back that section looks.
    var recentModelsWindow: RecentModelsWindow = .fifteenMinutes {
        didSet {
            defaults.set(recentModelsWindow.rawValue, forKey: "openrouter.recentModelsWindow")
            let window = recentModelsWindow
            Task { await pollingService.setRecentModelsWindow(window) }
        }
    }

    let sessionPreferences: SessionTrackingPreferences
    let sessionTracker: SessionTracker
    let menuBarText: MenuBarTextPreferences

    private let defaults: UserDefaults
    private let apiClient: OpenRouterAPIClient
    private let credentialStore: OpenRouterCredentialStore
    private let pollingService: OpenRouterBudgetPollingService
    private let snapshotStore: OpenRouterSnapshotStore
    private var credentialRetryTask: Task<Void, Never>?
    private let credentialRetryDelay: TimeInterval = 60

    init(
        secureStore: any SecureStore,
        defaults: UserDefaults = .standard,
        apiClient: OpenRouterAPIClient = OpenRouterAPIClient()
    ) {
        self.defaults = defaults
        self.apiClient = apiClient
        self.credentialStore = OpenRouterCredentialStore(secureStore: secureStore)
        self.pollingService = OpenRouterBudgetPollingService(apiClient: apiClient)
        self.snapshotStore = OpenRouterSnapshotStore(defaults: defaults)
        self.sessionPreferences = SessionTrackingPreferences(namespace: "openrouter", defaults: defaults)
        self.sessionTracker = SessionTracker(namespace: "openrouter", defaults: defaults)
        self.menuBarText = MenuBarTextPreferences(namespace: "openrouter", defaults: defaults)

        restorePreferences()
        setupCallbacks()
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isDemoMode else { return }
        connectionState = .validating
        AppRuntimeState.recordBreadcrumb("provider-openrouter-check-credential")

        let stored: OpenRouterManagementKey?
        do {
            stored = try await credentialStore.load()
        } catch {
            // Keychain locked: keep the cached snapshot, retry shortly, do not disconnect.
            AppRuntimeState.recordBreadcrumb("provider-openrouter-keychain-unavailable")
            restoreCachedSnapshot()
            connectionState = snapshot.isEmpty ? .disconnected : .connected(Self.placeholderIdentity)
            errorMessage = String(localized: "Keychain is locked. Retrying shortly.")
            scheduleCredentialRetry()
            return
        }

        guard let stored else {
            connectionState = .disconnected
            snapshotStore.clear()
            AppRuntimeState.recordBreadcrumb("provider-openrouter-credential-missing")
            return
        }

        restoreCachedSnapshot()
        await apiClient.setCredential(stored.key)

        do {
            let identity = try await apiClient.validateKey(stored.key)
            connectionState = .connected(identity)
            errorMessage = nil
            AppRuntimeState.recordBreadcrumb("provider-openrouter-credential-validated")
            await pollingService.setInterval(TimeInterval(pollingIntervalMinutes * 60))
            await pollingService.start()
        } catch let error as OpenRouterAPIError {
            if error.isTransient {
                // Offline at launch: keep the cached snapshot and let polling retry.
                connectionState = .connected(Self.placeholderIdentity)
                errorMessage = error.errorDescription
                await pollingService.start()
            } else {
                connectionState = .invalidKey(error.errorDescription ?? "")
            }
        } catch {
            connectionState = .invalidKey(error.localizedDescription)
        }
    }

    private static var placeholderIdentity: KeyIdentity {
        KeyIdentity(label: String(localized: "OpenRouter key"),
                    isManagementKey: true, isFreeTier: false, expiresAt: nil)
    }

    private func scheduleCredentialRetry() {
        credentialRetryTask?.cancel()
        credentialRetryTask = Task { [weak self, credentialRetryDelay] in
            try? await Task.sleep(for: .seconds(credentialRetryDelay))
            guard !Task.isCancelled else { return }
            await self?.start()
        }
    }

    /// Validates and stores a pasted key. Returns true when the connection succeeded.
    /// The key is written only after OpenRouter confirmed it is a management key.
    func connect(with rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        connectError = nil

        guard key.hasPrefix("sk-or-"), key.count > 20 else {
            connectError = String(localized: "That does not look like an OpenRouter key.")
            return false
        }

        isLoading = true
        let previousState = connectionState
        connectionState = .validating
        defer { isLoading = false }

        do {
            let identity = try await apiClient.validateKey(key)
            try await credentialStore.save(
                OpenRouterManagementKey(key: key, keyLabel: identity.label, validatedAt: Date())
            )
            await apiClient.setCredential(key)
            isDemoMode = false
            connectionState = .connected(identity)
            errorMessage = nil
            AppRuntimeState.recordBreadcrumb("provider-openrouter-connected")
            await pollingService.resetSteadyState()
            await pollingService.setInterval(TimeInterval(pollingIntervalMinutes * 60))
            await pollingService.start()
            return true
        } catch let error as OpenRouterAPIError {
            connectError = error.errorDescription
            connectionState = previousState.showsBudgets ? previousState : .disconnected
            return false
        } catch {
            connectError = error.localizedDescription
            connectionState = previousState.showsBudgets ? previousState : .disconnected
            return false
        }
    }

    func refresh() async {
        guard connectionState.showsBudgets, !isDemoMode, !isLoading else { return }
        AppRuntimeState.recordBreadcrumb("provider-openrouter-manual-refresh")
        isLoading = true
        await pollingService.refreshNow()
        isLoading = false
    }

    func suspend() async {
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        await pollingService.stop()
        nextRefreshAt = nil
    }

    func resume() async {
        guard !isDemoMode else { return }
        if connectionState.showsBudgets {
            AppRuntimeState.recordBreadcrumb("provider-openrouter-poll-start")
            await pollingService.setInterval(TimeInterval(pollingIntervalMinutes * 60))
            await pollingService.start()
        } else {
            await start()
        }
    }

    /// Deletes only PlanTracker's copy of the key. It stays valid at OpenRouter.
    func disconnect() async {
        AppRuntimeState.recordBreadcrumb("provider-openrouter-disconnect")
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        await pollingService.stop()
        await pollingService.resetSteadyState()
        await credentialStore.clear()
        await apiClient.setCredential(nil)
        connectionState = .disconnected
        snapshot = .empty
        lastUpdated = nil
        errorMessage = nil
        degradedMessage = nil
        isStale = false
        isDemoMode = false
        nextRefreshAt = nil
        snapshotStore.clear()
        CacheJanitor.cleanupTransientCaches(reason: "openrouter-disconnect")
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) async {
        await pollingService.handleMemoryPressure(level)
    }

    var dailySessionFormatted: String? {
        guard sessionPreferences.isEnabled else { return nil }
        return SessionTimeFormatter.line(totalSeconds: sessionTracker.totalSeconds)
    }

    // MARK: - Wiring

    private func setupCallbacks() {
        Task { [weak self] in
            guard let self else { return }
            // `[weak self]` on each callback, not just on the inner `Task`: the enclosing
            // `guard let self` promotes it to a strong local, and the actor outlives this call —
            // capturing that local would retain the view model that owns the actor.
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

    private func apply(_ outcome: PollOutcome) {
        guard !isDemoMode else { return }
        snapshot = outcome.snapshot
        lastUpdated = outcome.snapshot.fetchedAt
        isStale = false
        errorMessage = nil
        degradedMessage = outcome.degradedReason
        if sessionPreferences.isEnabled {
            sessionTracker.processTick(
                signals: Self.activitySignals(for: outcome.snapshot),
                minInterval: sessionPreferences.checkInterval,
                resetHour: sessionPreferences.resetHour
            )
        }
        snapshotStore.save(outcome.snapshot, at: outcome.snapshot.fetchedAt)
    }

    /// Lifetime spend only ever grows, so any movement is consumption. The remaining
    /// balance is deliberately not used: a top-up would read as activity.
    static func activitySignals(for snapshot: OpenRouterSnapshot) -> [ActivitySignal] {
        var signals: [ActivitySignal] = []
        if let credit = snapshot.accountCredit,
           let totalUsed = ActivitySignal.amount("totalUsed", credit.totalUsed) {
            signals.append(totalUsed)
        }
        if let today = snapshot.spentToday, today > Money.residueThreshold,
           let spentToday = ActivitySignal.amount("spentToday", today) {
            signals.append(spentToday)
        } else if snapshot.spentToday != nil {
            signals.append(ActivitySignal(id: "spentToday", value: 0, quantum: 1))
        }
        return signals
    }

    private func apply(_ error: OpenRouterAPIError) {
        guard !isDemoMode else { return }
        errorMessage = error.errorDescription
        if !snapshot.isEmpty { isStale = true }
        if error == .unauthorized || error == .notAManagementKey {
            connectionState = .invalidKey(error.errorDescription ?? "")
        }
    }

    private func restoreCachedSnapshot() {
        guard let stored = snapshotStore.load() else { return }
        snapshot = stored.snapshot
        lastUpdated = stored.lastSuccess
        isStale = true
    }

    private func restorePreferences() {
        if let raw = defaults.string(forKey: "openrouter.menuBarDisplay"),
           let display = MenuBarDisplay(rawValue: raw) {
            menuBarDisplay = display
        }
        showDisabledKeys = defaults.bool(forKey: "openrouter.showDisabledKeys")
        showRecentModels = defaults.bool(forKey: "openrouter.showRecentModels")
        if let raw = defaults.object(forKey: "openrouter.recentModelsWindow") as? Int,
           let window = RecentModelsWindow(rawValue: raw) {
            recentModelsWindow = window
        }
        spendBreakdownExpanded = defaults.bool(forKey: "openrouter.spendBreakdownExpanded")
    }
}

// MARK: - Reviewer mode

extension OpenRouterBudgetViewModel: DemoCapable {
    func enterDemo() {
        guard !isDemoMode else { return }
        isDemoMode = true
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        Task { await pollingService.stop() }
        nextRefreshAt = nil
        snapshot = DemoSnapshot.make()
        lastUpdated = snapshot.fetchedAt
        isStale = false
        errorMessage = nil
        degradedMessage = nil
        connectionState = .connected(
            KeyIdentity(label: "sk-or-v1-demo...000", isManagementKey: true,
                        isFreeTier: false, expiresAt: nil)
        )
        sessionTracker.setMockAccumulated(83 * 60)
    }
}

nonisolated enum MenuBarDisplay: String, CaseIterable, Sendable {
    case amount
    case percent
    case iconOnly

    var displayName: String {
        switch self {
        case .amount: String(localized: "Amount")
        case .percent: String(localized: "Percent")
        case .iconOnly: String(localized: "Icon only")
        }
    }
}
