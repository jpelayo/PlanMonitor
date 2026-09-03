//
//  ClaudeUsageViewModel.swift
//  PlanTracker
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class ClaudeUsageViewModel {
    private(set) var authState: ClaudeAuthState = .unknown
    private(set) var usageData: ClaudeUsageData = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isDemoMode = false
    private(set) var claudeSystemStatus: ClaudeSystemStatus = .degraded
    private(set) var claudeStatusSourceUpdatedAt: Date?
    /// The polling service's real next deadline. `nil` while no poll is scheduled.
    private(set) var nextRefreshAt: Date?

    private let snapshotStore: PersistedUsageSnapshotStore
    private var isFetchingClaudeStatus = false
    private var lastClaudeStatusFetchAt: Date?
    private let claudeStatusRefreshInterval: TimeInterval = 5 * 60
    private let claudeStatusSignalWindow: TimeInterval = 24 * 60 * 60
    private let credentialRetryDelay: TimeInterval = 60

    var pollingIntervalMinutes: Int = 5 {
        didSet {
            let seconds = TimeInterval(pollingIntervalMinutes * 60)
            Task { await pollingService.setPollingInterval(seconds) }
        }
    }

    var showRemainingPercent: Bool = true

    let sessionPreferences: SessionTrackingPreferences
    let sessionTracker: SessionTracker
    let menuBarText: MenuBarTextPreferences

    private let apiClient: ClaudeAPIClient
    private let authService: ClaudeAuthenticationService
    private let pollingService: ClaudeUsagePollingService
    private let cookieManager: ClaudeWebViewCookieManager
    private let claudeStatusService: ClaudeStatusService

    // Work that outlives the call that started it, so `suspend()` can cancel it.
    private var identityTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var credentialRetryTask: Task<Void, Never>?
    private var logoutTask: Task<Void, Never>?

    init(
        secureStore: any SecureStore,
        defaults: UserDefaults = .standard,
        apiClient: ClaudeAPIClient = ClaudeAPIClient()
    ) {
        self.apiClient = apiClient
        self.authService = ClaudeAuthenticationService(
            credentialStore: ClaudeCredentialStore(secureStore: secureStore),
            apiClient: apiClient,
            defaults: defaults
        )
        self.pollingService = ClaudeUsagePollingService(apiClient: apiClient)
        self.cookieManager = ClaudeWebViewCookieManager()
        self.claudeStatusService = ClaudeStatusService()
        self.snapshotStore = PersistedUsageSnapshotStore(defaults: defaults)
        self.sessionPreferences = SessionTrackingPreferences(namespace: "claude", defaults: defaults)
        self.sessionTracker = SessionTracker(namespace: "claude", defaults: defaults)
        self.menuBarText = MenuBarTextPreferences(namespace: "claude", defaults: defaults)

        restorePersistedSnapshot()
        setupPollingCallbacks()
    }

    private func setupPollingCallbacks() {
        Task {
            await pollingService.setCallbacks(
                onUsageUpdate: { [weak self] usage in
                    Task { @MainActor [weak self] in
                        self?.apply(usage)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.handleError(error)
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

    private func apply(_ usage: ClaudeUsageData) {
        guard !isDemoMode else { return }
        let usageChanged = usageData != usage
        usageData = usage
        lastUpdated = Date()
        errorMessage = nil
        if sessionPreferences.isEnabled {
            sessionTracker.processTick(
                signals: [
                    .percent("fiveHour", usage.fiveHourUtilization),
                    .minorUnits("prepaid", usage.prepaidCreditsRemaining),
                    .minorUnits("overage", usage.overageUsedCredits)
                ].compactMap { $0 },
                minInterval: sessionPreferences.checkInterval,
                resetHour: sessionPreferences.resetHour
            )
        }
        if usageChanged {
            persistUsageSnapshot()
        }
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            await self?.refreshClaudeStatus(force: false)
        }
    }

    func checkAuthentication() async {
        guard !isDemoMode else { return }
        isLoading = true
        authState = .unknown
        AppRuntimeState.recordBreadcrumb("provider-claude-check-authentication")

        switch await authService.restoreStoredSession() {
        case .restored(let identity):
            AppRuntimeState.recordBreadcrumb("provider-claude-auth-restored-keychain")
            authState = .restoring(email: identity)
            errorMessage = nil
            await startPolling()
            isLoading = false
            identityTask?.cancel()
            identityTask = Task { [weak self] in
                await self?.refreshRestoredIdentity()
            }
            return
        case .unavailable:
            // The secret exists but the Keychain would not release it. Keep whatever the
            // cached snapshot shows and try again shortly; this is not a sign-out.
            AppRuntimeState.recordBreadcrumb("provider-claude-auth-keychain-unavailable")
            authState = .restoring(email: nil)
            isLoading = false
            scheduleCredentialRetry()
            return
        case .absent:
            break
        }

        if let cookieString = await cookieManager.extractSessionCookies() {
            AppRuntimeState.recordBreadcrumb("provider-claude-auth-restored-webview")
            await handleLoginSuccess(sessionKey: cookieString)
            isLoading = false
            return
        }

        AppRuntimeState.recordBreadcrumb("provider-claude-auth-missing")
        authState = .unauthenticated
        isLoading = false
    }

    private func scheduleCredentialRetry() {
        credentialRetryTask?.cancel()
        credentialRetryTask = Task { [weak self, credentialRetryDelay] in
            try? await Task.sleep(for: .seconds(credentialRetryDelay))
            guard !Task.isCancelled else { return }
            await self?.checkAuthentication()
        }
    }

    private func refreshRestoredIdentity() async {
        do {
            let email = try await authService.refreshCachedIdentity()
            guard authState.isAuthenticated, !Task.isCancelled else { return }
            AppRuntimeState.recordBreadcrumb("provider-claude-auth-identity-refreshed")
            authState = .authenticated(email: email)
        } catch let error as ClaudeAPIClient.APIError {
            switch error {
            case .unauthorized, .forbidden:
                handleError(error)
            default:
                break
            }
        } catch {
            // Malformed or transient: keep the restored state.
        }
    }

    func handleLoginSuccess(sessionKey: String) async {
        isLoading = true
        authState = .authenticating

        do {
            try await authService.saveSessionKey(sessionKey)
            let email = try await authService.validateSession()
            AppRuntimeState.recordBreadcrumb("provider-claude-login-success")
            isDemoMode = false
            authState = .authenticated(email: email)
            await startPolling()
        } catch {
            handleError(error)
            authState = .unauthenticated
        }

        isLoading = false
    }

    func logout() async {
        AppRuntimeState.recordBreadcrumb("provider-claude-logout")
        cancelBackgroundWork()
        await pollingService.stopPolling()
        await pollingService.resetSteadyState()
        try? await authService.clearCredentials()

        // Also clear WebView cookies
        await cookieManager.clearSessionCookies()

        authState = .unauthenticated
        usageData = .empty
        lastUpdated = nil
        errorMessage = nil
        isDemoMode = false
        snapshotStore.clear()
        CacheJanitor.cleanupTransientCaches(reason: "claude-logout")
    }

    func refreshUsage() async {
        guard authState.isAuthenticated, !isDemoMode, !isLoading else { return }
        AppRuntimeState.recordBreadcrumb("provider-claude-manual-refresh")
        isLoading = true
        await pollingService.fetchUsage(forceMetadataRefresh: true)
        await refreshClaudeStatus(force: true)
        isLoading = false
    }

    func suspend() async {
        cancelBackgroundWork()
        await pollingService.stopPolling()
        nextRefreshAt = nil
    }

    func resume() async {
        guard !isDemoMode else { return }
        if authState.isAuthenticated {
            await startPolling()
        } else {
            await checkAuthentication()
        }
    }

    private func cancelBackgroundWork() {
        identityTask?.cancel()
        statusTask?.cancel()
        credentialRetryTask?.cancel()
        identityTask = nil
        statusTask = nil
        credentialRetryTask = nil
    }

    private func startPolling() async {
        AppRuntimeState.recordBreadcrumb("provider-claude-poll-start")
        let interval = TimeInterval(pollingIntervalMinutes * 60)
        await pollingService.setPollingInterval(interval)
        await pollingService.startPolling()
        await refreshClaudeStatus(force: true)
    }

    var displayedClaudeSystemStatus: ClaudeSystemStatus {
        guard let status = visibleClaudeSystemStatus else {
            return .operational
        }
        return status
    }

    var visibleClaudeSystemStatus: ClaudeSystemStatus? {
        guard let sourceUpdatedAt = claudeStatusSourceUpdatedAt else {
            return nil
        }
        guard isUsableClaudeStatusTimestamp(sourceUpdatedAt) else {
            return nil
        }
        switch claudeSystemStatus {
        case .operational:
            return nil
        case .degraded, .outage:
            return claudeSystemStatus
        }
    }

    var visibleClaudeStatusSourceUpdatedAt: Date? {
        guard let sourceUpdatedAt = claudeStatusSourceUpdatedAt else {
            return nil
        }
        guard isUsableClaudeStatusTimestamp(sourceUpdatedAt) else {
            return nil
        }
        return sourceUpdatedAt
    }

    var dailySessionFormatted: String? {
        guard sessionPreferences.isEnabled else { return nil }
        return SessionTimeFormatter.line(totalSeconds: sessionTracker.totalSeconds)
    }

    private func handleError(_ error: Error) {
        if let apiError = error as? ClaudeAPIClient.APIError {
            switch apiError {
            case .unauthorized, .forbidden:
                logoutTask?.cancel()
                logoutTask = Task { [weak self] in
                    await self?.logout()
                }
                errorMessage = apiError.errorDescription
            default:
                setNonCriticalErrorMessage(apiError.errorDescription)
            }
        } else {
            setNonCriticalErrorMessage(error.localizedDescription)
        }
    }

    private func setNonCriticalErrorMessage(_ message: String?) {
        guard shouldShowNonCriticalError else {
            errorMessage = nil
            return
        }
        errorMessage = message
    }

    private var shouldShowNonCriticalError: Bool {
        if case .authenticating = authState {
            return true
        }
        return usageData == .empty && lastUpdated == nil
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) async {
        guard authState.isAuthenticated else { return }
        await pollingService.handleMemoryPressure(level)
    }

    private func restorePersistedSnapshot() {
        guard let snapshot = snapshotStore.load() else { return }
        usageData = snapshot.usageData
        lastUpdated = snapshot.lastUpdated
        AppRuntimeState.recordBreadcrumb("provider-claude-snapshot-restored")
    }

    private func persistUsageSnapshot() {
        guard !isDemoMode else { return }
        snapshotStore.save(usageData: usageData, lastUpdated: lastUpdated)
    }

    private func refreshClaudeStatus(force: Bool) async {
        guard !isDemoMode else { return }
        let now = Date()
        if !force,
           let lastFetch = lastClaudeStatusFetchAt,
           now.timeIntervalSince(lastFetch) < claudeStatusRefreshInterval {
            return
        }

        guard !isFetchingClaudeStatus else { return }
        isFetchingClaudeStatus = true
        lastClaudeStatusFetchAt = now
        defer { isFetchingClaudeStatus = false }

        do {
            let snapshot = try await claudeStatusService.fetchStatus()
            guard !Task.isCancelled else { return }
            if let incomingUpdatedAt = snapshot.sourceUpdatedAt,
               let existingUpdatedAt = claudeStatusSourceUpdatedAt,
               incomingUpdatedAt < existingUpdatedAt {
                return
            }
            if snapshot.sourceUpdatedAt == nil, claudeStatusSourceUpdatedAt != nil {
                return
            }
            claudeSystemStatus = snapshot.status
            claudeStatusSourceUpdatedAt = snapshot.sourceUpdatedAt
        } catch {
            // Keep previous status value on transient failures.
        }
    }

    private func isUsableClaudeStatusTimestamp(_ sourceUpdatedAt: Date) -> Bool {
        let now = Date()
        if sourceUpdatedAt > now.addingTimeInterval(120) {
            return false
        }
        return now.timeIntervalSince(sourceUpdatedAt) <= claudeStatusSignalWindow
    }
}

// MARK: - Reviewer mode

extension ClaudeUsageViewModel: DemoCapable {
    /// Deterministic data for App Review. Stops live work first and persists nothing.
    func enterDemo() {
        guard !isDemoMode else { return }
        isDemoMode = true
        cancelBackgroundWork()
        Task { await pollingService.stopPolling() }
        nextRefreshAt = nil
        authState = .authenticated(email: "demo@example.com")

        let now = Date()
        let fiveHourReset = now.addingTimeInterval(3 * 3600) // 3 hours from now
        let sevenDayReset = now.addingTimeInterval(4 * 24 * 3600) // 4 days from now

        usageData = ClaudeUsageData(
            fiveHourUtilization: 42.0,
            fiveHourResetsAt: fiveHourReset,
            sevenDayUtilization: 67.5,
            sevenDayResetsAt: sevenDayReset,
            sevenDayOpusUtilization: 23.0,
            sevenDayOpusResetsAt: sevenDayReset,
            sevenDaySonnetUtilization: 81.2,
            sevenDaySonnetResetsAt: sevenDayReset,
            sevenDayScopedLabel: "Fable",
            sevenDayScopedUtilization: 23.0,
            sevenDayScopedResetsAt: sevenDayReset,
            extraUsageUtilization: 15.5,
            extraUsageResetsAt: sevenDayReset,
            planTier: .pro,
            planDisplayNameOverride: nil,
            prepaidCreditsRemaining: 4280,  // $42.80
            prepaidCreditsTotal: 5000,      // $50.00
            prepaidCreditsCurrency: "USD",
            prepaidCreditsArePromotional: false,
            prepaidAutoReloadEnabled: false,
            paidCreditsRemaining: 1000,
            paidCreditsTotal: 1000,
            paidCreditsCurrency: "USD",
            pendingInvoiceAmount: nil,
            overageMonthlyLimit: 5000,      // $50.00
            overageUsedCredits: 1359,       // $13.59
            overageCurrency: "USD",
            overageEnabled: true,
            overageOutOfCredits: false
        )

        lastUpdated = now
        errorMessage = nil
        claudeSystemStatus = .operational
        claudeStatusSourceUpdatedAt = now
        sessionTracker.setMockAccumulated(83 * 60) // 1h 23m
    }
}

// MARK: - Snapshot persistence

private struct PersistedUsageSnapshot: Codable {
    let schemaVersion: Int
    let providerID: ProviderID
    let usageData: ClaudeUsageData
    let lastUpdated: Date?
    let savedAt: Date
}

private struct PersistedUsageSnapshotStore {
    private let defaults: UserDefaults
    private let key = "claude.persistedUsageSnapshot.v2"
    private let legacyKey = "persistedUsageSnapshot.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> PersistedUsageSnapshot? {
        if let data = defaults.data(forKey: key),
           let snapshot = try? JSONDecoder().decode(PersistedUsageSnapshot.self, from: data),
           snapshot.schemaVersion == 2,
           snapshot.providerID == .claude {
            return snapshot
        }

        guard let data = defaults.data(forKey: legacyKey),
              let legacy = try? JSONDecoder().decode(LegacyPersistedUsageSnapshot.self, from: data) else {
            return nil
        }
        let migrated = PersistedUsageSnapshot(
            schemaVersion: 2,
            providerID: .claude,
            usageData: legacy.usageData,
            lastUpdated: legacy.lastUpdated,
            savedAt: legacy.savedAt
        )
        if let migratedData = try? JSONEncoder().encode(migrated) {
            defaults.set(migratedData, forKey: key)
        }
        return migrated
    }

    func save(usageData: ClaudeUsageData, lastUpdated: Date?) {
        guard usageData != .empty else {
            clear()
            return
        }

        let snapshot = PersistedUsageSnapshot(
            schemaVersion: 2,
            providerID: .claude,
            usageData: usageData,
            lastUpdated: lastUpdated,
            savedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacyKey)
    }
}

private struct LegacyPersistedUsageSnapshot: Codable {
    let usageData: ClaudeUsageData
    let lastUpdated: Date?
    let savedAt: Date
}
