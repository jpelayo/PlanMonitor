//
//  CodexUsageViewModel.swift
//  PlanTracker
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class CodexUsageViewModel {
    private(set) var authState: CodexAuthState = .unknown
    private(set) var usageData: CodexUsageData = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isDemoMode = false
    private(set) var nextRefreshAt: Date?

    private let snapshotStore: PersistedUsageSnapshotStore
    private var isRecoveringAuth = false
    private var lastAuthRecoveryAttemptAt: Date?
    private let authRecoveryCooldown: TimeInterval = 60
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

    private let apiClient: OpenAIAPIClient
    private let authService: CodexAuthenticationService
    private let pollingService: CodexUsagePollingService
    private let cookieManager: CodexWebViewCookieManager

    private var identityTask: Task<Void, Never>?
    private var cookiePersistTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var credentialRetryTask: Task<Void, Never>?

    init(
        secureStore: any SecureStore,
        defaults: UserDefaults = .standard,
        apiClient: OpenAIAPIClient = OpenAIAPIClient()
    ) {
        self.apiClient = apiClient
        self.authService = CodexAuthenticationService(
            credentialStore: CodexCredentialStore(secureStore: secureStore),
            apiClient: apiClient,
            defaults: defaults
        )
        self.pollingService = CodexUsagePollingService(apiClient: apiClient)
        self.cookieManager = CodexWebViewCookieManager()
        self.snapshotStore = PersistedUsageSnapshotStore(defaults: defaults)
        self.sessionPreferences = SessionTrackingPreferences(namespace: "codex", defaults: defaults)
        self.sessionTracker = SessionTracker(namespace: "codex", defaults: defaults)
        self.menuBarText = MenuBarTextPreferences(namespace: "codex", defaults: defaults)

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

    private func apply(_ usage: CodexUsageData) {
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
        cookiePersistTask?.cancel()
        cookiePersistTask = Task { [weak self] in
            await self?.authService.persistCurrentSessionCookiesIfNeeded()
        }
    }

    func checkAuthentication() async {
        guard !isDemoMode else { return }
        isLoading = true
        authState = .unknown
        AppRuntimeState.recordBreadcrumb("provider-codex-check-authentication")

        switch await authService.restoreStoredSession() {
        case .restored(let identity):
            AppRuntimeState.recordBreadcrumb("provider-codex-auth-restored-keychain")
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
            AppRuntimeState.recordBreadcrumb("provider-codex-auth-keychain-unavailable")
            authState = .restoring(email: nil)
            isLoading = false
            scheduleCredentialRetry()
            return
        case .absent:
            break
        }

        if let cookieString = await cookieManager.extractSessionCookies() {
            AppRuntimeState.recordBreadcrumb("provider-codex-auth-restored-webview")
            _ = await handleLoginSuccess(sessionCookies: cookieString)
            isLoading = false
            return
        }

        AppRuntimeState.recordBreadcrumb("provider-codex-auth-missing")
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
            AppRuntimeState.recordBreadcrumb("provider-codex-auth-identity-refreshed")
            authState = .authenticated(email: email)
            await authService.persistCurrentSessionCookiesIfNeeded()
        } catch let error as OpenAIAPIClient.APIError {
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

    func handleLoginSuccess(sessionCookies: String) async -> Bool {
        isLoading = true
        authState = .authenticating

        do {
            try await authService.saveSessionCookies(sessionCookies)
            let email = try await authService.validateSession()
            AppRuntimeState.recordBreadcrumb("provider-codex-login-success")
            isDemoMode = false
            authState = .authenticated(email: email)
            await startPolling()
            isLoading = false
            return true
        } catch {
            handleError(error)
            authState = .unauthenticated
            isLoading = false
            return false
        }
    }

    func logout() async {
        AppRuntimeState.recordBreadcrumb("provider-codex-logout")
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
        CacheJanitor.cleanupTransientCaches(reason: "codex-logout")
    }

    func refreshUsage() async {
        guard authState.isAuthenticated, !isDemoMode, !isLoading else { return }
        AppRuntimeState.recordBreadcrumb("provider-codex-manual-refresh")
        isLoading = true
        await pollingService.fetchUsage(forceMetadataRefresh: true)
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
        cookiePersistTask?.cancel()
        recoveryTask?.cancel()
        credentialRetryTask?.cancel()
        identityTask = nil
        cookiePersistTask = nil
        recoveryTask = nil
        credentialRetryTask = nil
    }

    private func startPolling() async {
        AppRuntimeState.recordBreadcrumb("provider-codex-poll-start")
        let interval = TimeInterval(pollingIntervalMinutes * 60)
        await pollingService.setPollingInterval(interval)
        await pollingService.startPolling()
    }

    var dailySessionFormatted: String? {
        guard sessionPreferences.isEnabled else { return nil }
        return SessionTimeFormatter.line(totalSeconds: sessionTracker.totalSeconds)
    }

    private func handleError(_ error: Error) {
        if let apiError = error as? OpenAIAPIClient.APIError {
            switch apiError {
            case .unauthorized, .forbidden:
                recoveryTask?.cancel()
                recoveryTask = Task { @MainActor [weak self] in
                    await self?.recoverFromAuthorizationFailure(apiError)
                }
            default:
                setNonCriticalErrorMessage(apiError.errorDescription)
            }
        } else {
            setNonCriticalErrorMessage(error.localizedDescription)
        }
    }

    private func recoverFromAuthorizationFailure(_ apiError: OpenAIAPIClient.APIError) async {
        if case .authenticating = authState {
            errorMessage = apiError.errorDescription
            return
        }

        guard canAttemptAuthRecovery else {
            if !authState.isAuthenticated {
                authState = .unauthenticated
            }
            errorMessage = apiError.errorDescription
            return
        }

        isRecoveringAuth = true
        defer {
            isRecoveringAuth = false
            lastAuthRecoveryAttemptAt = Date()
        }

        AppRuntimeState.recordBreadcrumb("provider-codex-auth-recovery-start")

        if await recoverUsingStoredSession() {
            AppRuntimeState.recordBreadcrumb("provider-codex-auth-recovery-stored-session")
            errorMessage = nil
            return
        }

        if await recoverUsingWebViewCookies() {
            AppRuntimeState.recordBreadcrumb("provider-codex-auth-recovery-webview-cookies")
            errorMessage = nil
            return
        }

        AppRuntimeState.recordBreadcrumb("provider-codex-auth-recovery-failed")
        if !authState.isAuthenticated {
            authState = .unauthenticated
        }
        errorMessage = apiError.errorDescription
    }

    private var canAttemptAuthRecovery: Bool {
        guard !isRecoveringAuth else { return false }
        guard let lastAttempt = lastAuthRecoveryAttemptAt else { return true }
        return Date().timeIntervalSince(lastAttempt) >= authRecoveryCooldown
    }

    private func recoverUsingStoredSession() async -> Bool {
        guard case .restored(let identity) = await authService.restoreStoredSession() else {
            return false
        }

        if let identity, !authState.isAuthenticated {
            authState = .restoring(email: identity)
        }

        do {
            let email = try await authService.refreshCachedIdentity(forceRefresh: true)
            authState = .authenticated(email: email)
            await authService.persistCurrentSessionCookiesIfNeeded()
            return true
        } catch {
            return false
        }
    }

    private func recoverUsingWebViewCookies() async -> Bool {
        guard let cookieString = await cookieManager.extractSessionCookies() else {
            return false
        }

        do {
            try await authService.saveSessionCookies(cookieString)
            let email = try await authService.validateSession()
            authState = .authenticated(email: email)
            await authService.persistCurrentSessionCookiesIfNeeded()
            return true
        } catch {
            return false
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
        AppRuntimeState.recordBreadcrumb("provider-codex-snapshot-restored")
    }

    private func persistUsageSnapshot() {
        guard !isDemoMode else { return }
        snapshotStore.save(usageData: usageData, lastUpdated: lastUpdated)
    }
}

// MARK: - Reviewer mode

extension CodexUsageViewModel: DemoCapable {
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

        usageData = CodexUsageData(
            fiveHourUtilization: 42.0,
            fiveHourResetsAt: fiveHourReset,
            sevenDayUtilization: 67.5,
            sevenDayResetsAt: sevenDayReset,
            sevenDayOpusUtilization: 23.0,
            sevenDayOpusResetsAt: sevenDayReset,
            sevenDayOpusName: "Code Review",
            sevenDaySonnetUtilization: 81.2,
            sevenDaySonnetResetsAt: sevenDayReset,
            sevenDaySonnetName: "Additional Weekly Limit",
            extraUsageUtilization: 15.5,
            extraUsageResetsAt: sevenDayReset,
            extraUsageName: "Additional Limit",
            planTier: .pro,
            prepaidCreditsRemaining: 4280,  // $42.80
            prepaidCreditsTotal: 5000,      // $50.00
            prepaidCreditsCurrency: "USD",
            prepaidAutoReloadEnabled: false,
            overageMonthlyLimit: 5000,      // $50.00
            overageUsedCredits: 1359,       // $13.59
            overageCurrency: "USD",
            overageEnabled: true,
            overageOutOfCredits: false
        )

        lastUpdated = now
        errorMessage = nil
        sessionTracker.setMockAccumulated(83 * 60) // 1h 23m
    }
}

// MARK: - Snapshot persistence

private struct PersistedUsageSnapshot: Codable {
    let schemaVersion: Int
    let providerID: ProviderID
    let usageData: CodexUsageData
    let lastUpdated: Date?
    let savedAt: Date
}

/// The shape written before the envelope carried a version and provider.
private struct LegacyPersistedUsageSnapshot: Codable {
    let usageData: CodexUsageData
    let lastUpdated: Date?
    let savedAt: Date
}

private struct PersistedUsageSnapshotStore {
    private let defaults: UserDefaults
    private let key = "codex.persistedUsageSnapshot.v2"
    private let legacyKey = "codex.persistedUsageSnapshot.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> PersistedUsageSnapshot? {
        if let data = defaults.data(forKey: key),
           let snapshot = try? JSONDecoder().decode(PersistedUsageSnapshot.self, from: data),
           snapshot.schemaVersion == 2,
           snapshot.providerID == .codex {
            return snapshot
        }

        guard let data = defaults.data(forKey: legacyKey),
              let legacy = try? JSONDecoder().decode(LegacyPersistedUsageSnapshot.self, from: data) else {
            return nil
        }
        let migrated = PersistedUsageSnapshot(
            schemaVersion: 2,
            providerID: .codex,
            usageData: legacy.usageData,
            lastUpdated: legacy.lastUpdated,
            savedAt: legacy.savedAt
        )
        if let migratedData = try? JSONEncoder().encode(migrated) {
            defaults.set(migratedData, forKey: key)
        }
        return migrated
    }

    func save(usageData: CodexUsageData, lastUpdated: Date?) {
        guard usageData != .empty else {
            clear()
            return
        }

        let snapshot = PersistedUsageSnapshot(
            schemaVersion: 2,
            providerID: .codex,
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
