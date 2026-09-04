import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class GrokUsageViewModel {
    private(set) var authState: GrokAuthState = .unauthenticated
    private(set) var usageData: GrokUsageData = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isStale = false
    private(set) var isDemoMode = false
    private(set) var grokSystemStatus: GrokSystemStatus = .degraded
    private(set) var grokStatusSourceUpdatedAt: Date?
    private(set) var nextRefreshAt: Date?
    var needsUsageAuthorization = false

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

    private let apiClient: GrokAPIClient
    private let authService: GrokAuthenticationService
    private let pollingService: GrokUsagePollingService
    private let cookieManager: GrokWebViewCookieManager
    private let snapshotStore: GrokUsageSnapshotStore
    private let grokStatusService: GrokStatusService
    private var pendingDeviceAuthorization: GrokDeviceAuthorization?
    /// The letters the approval page shows. Displayed in the login window and the dropdown
    /// so the user can check the page belongs to this request before pressing Continue.
    private(set) var pendingUserCode: String?
    private var credentialRetryTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private let credentialRetryDelay: TimeInterval = 60
    private let grokStatusRefreshInterval: TimeInterval = 5 * 60
    private let grokStatusSignalWindow: TimeInterval = 24 * 60 * 60
    private var isFetchingGrokStatus = false
    private var lastGrokStatusFetchAt: Date?

    init(
        secureStore: any SecureStore,
        defaults: UserDefaults = .standard,
        apiClient: GrokAPIClient = GrokAPIClient(),
        oidcClient: GrokOIDCClient = GrokOIDCClient()
    ) {
        let store = GrokCredentialStore(secureStore: secureStore)
        self.apiClient = apiClient
        self.authService = GrokAuthenticationService(
            apiClient: apiClient,
            oidcClient: oidcClient,
            credentialStore: store
        )
        self.pollingService = GrokUsagePollingService(apiClient: apiClient)
        self.cookieManager = GrokWebViewCookieManager()
        self.grokStatusService = GrokStatusService()
        self.snapshotStore = GrokUsageSnapshotStore(defaults: defaults)
        self.sessionPreferences = SessionTrackingPreferences(namespace: "grok", defaults: defaults)
        self.sessionTracker = SessionTracker(namespace: "grok", defaults: defaults)
        self.menuBarText = MenuBarTextPreferences(namespace: "grok", defaults: defaults)

        setupPollingCallbacks()
    }

    func checkAuthentication() async {
        if isDemoMode { return }
        isLoading = true
        authState = .restoring
        AppRuntimeState.recordBreadcrumb("provider-grok-check-authentication")

        let restored: (email: String?, hasUsageToken: Bool)
        switch await authService.restoreStoredSession() {
        case .absent:
            snapshotStore.clear()
            usageData = .empty
            authState = .unauthenticated
            isLoading = false
            AppRuntimeState.recordBreadcrumb("provider-grok-auth-missing")
            return
        case .unavailable:
            // Keychain locked: keep the cached snapshot, retry shortly, do not sign out.
            AppRuntimeState.recordBreadcrumb("provider-grok-auth-keychain-unavailable")
            restorePersistedSnapshot()
            authState = .restoring
            isLoading = false
            scheduleCredentialRetry()
            return
        case .restored(let email, let hasUsageToken):
            restored = (email, hasUsageToken)
        }

        AppRuntimeState.recordBreadcrumb("provider-grok-auth-restored-keychain")
        let email: String
        if let restoredEmail = restored.email {
            email = restoredEmail
        } else if let validated = try? await authService.validateSession() {
            email = validated
        } else {
            email = String(localized: "Signed in")
        }
        authState = .authenticated(
            AccountIdentity(
                email: email,
                displayName: email,
                principalType: "User",
                isPersonalAccount: true
            )
        )
        restorePersistedSnapshot()
        errorMessage = nil
        isLoading = false
        if restored.hasUsageToken {
            await startPolling()
        } else {
            needsUsageAuthorization = true
        }
    }

    private func scheduleCredentialRetry() {
        credentialRetryTask?.cancel()
        credentialRetryTask = Task { [weak self, credentialRetryDelay] in
            try? await Task.sleep(for: .seconds(credentialRetryDelay))
            guard !Task.isCancelled else { return }
            await self?.checkAuthentication()
        }
    }

    func handleLoginSuccess(sessionCookies: String) async -> Bool {
        isLoading = true
        authState = .importing
        guard GrokWebViewCookieManager.cookieHeaderContainsSession(sessionCookies) else {
            authState = .unauthenticated
            isLoading = false
            return false
        }
        do {
            try await authService.saveSessionCookies(sessionCookies)
            let email = try await authService.validateSession()
            isDemoMode = false
            authState = .authenticated(
                AccountIdentity(
                    email: email,
                    displayName: email,
                    principalType: "User",
                    isPersonalAccount: true
                )
            )
            errorMessage = nil
            isLoading = false
            AppRuntimeState.recordBreadcrumb("provider-grok-login-success")
            return true
        } catch {
            needsUsageAuthorization = true
            isLoading = false
            return false
        }
    }

    func startDeviceAuthorization() async throws -> URL {
        let authorization = try await authService.startDeviceAuthorization()
        pendingDeviceAuthorization = authorization
        pendingUserCode = authorization.userCode
        return authorization.verificationURL
    }

    func completeDeviceAuthorization() async throws {
        guard let authorization = pendingDeviceAuthorization else {
            throw GrokOIDCError.invalidResponse
        }
        let credentials = try await authService.completeDeviceAuthorization(
            authorization,
            email: authState.email
        )
        pendingDeviceAuthorization = nil
        pendingUserCode = nil
        needsUsageAuthorization = false
        isDemoMode = false
        authState = .authenticated(credentials.identity)
        errorMessage = nil
        AppRuntimeState.recordBreadcrumb("provider-grok-oidc-authorized")
        await startPolling()
    }

    func storedCookies() async -> String? {
        await authService.storedCookies()
    }

    func refreshUsage() async {
        guard authState.showsUsage, !isDemoMode, !isLoading else { return }
        AppRuntimeState.recordBreadcrumb("provider-grok-manual-refresh")
        isLoading = true
        await pollingService.fetchUsage(forceMetadataRefresh: true)
        await refreshGrokStatus(force: true)
        isLoading = false
    }

    func suspend() async {
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        statusTask?.cancel()
        statusTask = nil
        await pollingService.stopPolling()
        nextRefreshAt = nil
    }

    func resume() async {
        guard !isDemoMode else { return }
        if authState.showsUsage, !needsUsageAuthorization {
            await startPolling()
        } else {
            await checkAuthentication()
        }
    }

    func logout() async {
        AppRuntimeState.recordBreadcrumb("provider-grok-logout")
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        await pollingService.stopPolling()
        await pollingService.resetSteadyState()
        try? await authService.clearCredentials()
        await cookieManager.clearSessionCookies()
        await GrokWebsiteDataStore.removeAll()
        authState = .unauthenticated
        usageData = .empty
        lastUpdated = nil
        errorMessage = nil
        isStale = false
        isDemoMode = false
        needsUsageAuthorization = false
        pendingDeviceAuthorization = nil
        pendingUserCode = nil
        snapshotStore.clear()
        CacheJanitor.cleanupTransientCaches(reason: "grok-logout")
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) async {
        guard authState.showsUsage else { return }
        await pollingService.handleMemoryPressure(level)
    }

    var dailySessionFormatted: String? {
        guard sessionPreferences.isEnabled else { return nil }
        return SessionTimeFormatter.line(totalSeconds: sessionTracker.totalSeconds)
    }

    // MARK: - Private

    private func startPolling() async {
        AppRuntimeState.recordBreadcrumb("provider-grok-poll-start")
        let interval = TimeInterval(pollingIntervalMinutes * 60)
        await pollingService.setPollingInterval(interval)
        await pollingService.startPolling()
        await refreshGrokStatus(force: true)
    }

    private func setupPollingCallbacks() {
        Task {
            let auth = authService
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
                prepare: { force in
                    try await auth.refreshAccessTokenIfNeeded(force: force)
                },
                onSchedule: { [weak self] date in
                    Task { @MainActor [weak self] in
                        self?.nextRefreshAt = date
                    }
                }
            )
        }
    }

    private func apply(_ usage: GrokUsageData) {
        guard !isDemoMode else { return }
        usageData = usage
        lastUpdated = usage.fetchedAt
        isStale = false
        errorMessage = nil
        if sessionPreferences.isEnabled {
            sessionTracker.processTick(
                signals: Self.activitySignals(for: usage),
                minInterval: sessionPreferences.checkInterval,
                resetHour: sessionPreferences.resetHour
            )
        }
        persistSnapshot()
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            await self?.refreshGrokStatus(force: false)
        }
    }

    /// Weekly pool utilization is the primary signal; it is a 0…1 fraction on the wire, so
    /// use the percent accessor. Money signals are compared at cent resolution.
    static func activitySignals(for usage: GrokUsageData) -> [ActivitySignal] {
        var signals: [ActivitySignal] = []
        if let percent = ActivitySignal.percent("weekly", usage.usedPercent) {
            signals.append(percent)
        } else if let limit = usage.monthlyLimit, let used = usage.monthlyUsed, limit > 0,
                  let percent = ActivitySignal.percent("monthly", min((used / limit) * 100, 100)) {
            signals.append(percent)
        }
        if let prepaid = ActivitySignal.amount("prepaid", usage.prepaidBalance) {
            signals.append(prepaid)
        }
        if let onDemand = ActivitySignal.amount("onDemand", usage.onDemandUsed) {
            signals.append(onDemand)
        }
        return signals
    }

    private func handleError(_ error: Error) {
        if let apiError = error as? GrokAPIError {
            switch apiError {
            case .noSessionCookies:
                authState = .unauthenticated
                errorMessage = nil
                return
            case .unauthorized, .noAccessToken:
                needsUsageAuthorization = true
                return
            case .noWeeklyUsage:
                // With nothing to show, say why; with cached usage, stay quiet.
                errorMessage = usageData == .empty ? apiError.localizedDescription : nil
                return
            case .forbidden, .unsupportedPrincipal:
                errorMessage = apiError.localizedDescription
                return
            default:
                break
            }
        }
        // Transient failures never replace cached usage. When there is no usage at all,
        // an empty "no limits" screen is a dead end, so the reason is shown instead.
        if usageData == .empty {
            errorMessage = (error as? GrokAPIError)?.localizedDescription ?? error.localizedDescription
            isStale = false
        } else {
            errorMessage = nil
            isStale = true
        }
    }

    private func persistSnapshot() {
        guard !isDemoMode else { return }
        snapshotStore.save(usage: usageData, lastSuccess: lastUpdated ?? Date())
    }

    private func restorePersistedSnapshot() {
        guard let snapshot = snapshotStore.load() else { return }
        usageData = snapshot.usage
        lastUpdated = snapshot.lastSuccess
        isStale = true
    }
}

// MARK: - Reviewer mode

extension GrokUsageViewModel: DemoCapable {
    var displayedGrokSystemStatus: GrokSystemStatus {
        guard let status = visibleGrokSystemStatus else {
            return .operational
        }
        return status
    }

    var visibleGrokSystemStatus: GrokSystemStatus? {
        guard let sourceUpdatedAt = grokStatusSourceUpdatedAt else {
            return nil
        }
        guard isUsableGrokStatusTimestamp(sourceUpdatedAt) else {
            return nil
        }
        switch grokSystemStatus {
        case .operational:
            return nil
        case .degraded, .outage:
            return grokSystemStatus
        }
    }

    private func refreshGrokStatus(force: Bool) async {
        guard !isDemoMode else { return }
        let now = Date()
        if !force,
           let lastFetch = lastGrokStatusFetchAt,
           now.timeIntervalSince(lastFetch) < grokStatusRefreshInterval {
            return
        }

        guard !isFetchingGrokStatus else { return }
        isFetchingGrokStatus = true
        lastGrokStatusFetchAt = now
        defer { isFetchingGrokStatus = false }

        do {
            let snapshot = try await grokStatusService.fetchStatus()
            guard !Task.isCancelled else { return }
            if let incomingUpdatedAt = snapshot.sourceUpdatedAt,
               let existingUpdatedAt = grokStatusSourceUpdatedAt,
               incomingUpdatedAt < existingUpdatedAt {
                return
            }
            if snapshot.sourceUpdatedAt == nil, grokStatusSourceUpdatedAt != nil {
                return
            }
            grokSystemStatus = snapshot.status
            grokStatusSourceUpdatedAt = snapshot.sourceUpdatedAt
        } catch {
            // Keep previous status value on transient failures.
        }
    }

    private func isUsableGrokStatusTimestamp(_ sourceUpdatedAt: Date) -> Bool {
        let now = Date()
        if sourceUpdatedAt > now.addingTimeInterval(120) {
            return false
        }
        return now.timeIntervalSince(sourceUpdatedAt) <= grokStatusSignalWindow
    }

    func enterDemo() {
        guard !isDemoMode else { return }
        isDemoMode = true
        credentialRetryTask?.cancel()
        credentialRetryTask = nil
        Task { await pollingService.stopPolling() }
        nextRefreshAt = nil
        needsUsageAuthorization = false
        let demo = DemoGrokUsage.snapshot()
        usageData = demo
        lastUpdated = demo.fetchedAt
        isStale = false
        errorMessage = nil
        grokSystemStatus = .operational
        grokStatusSourceUpdatedAt = Date()
        authState = .authenticated(
            AccountIdentity(
                email: "demo@example.com",
                displayName: "Demo",
                principalType: "User",
                isPersonalAccount: true
            )
        )
        sessionTracker.setMockAccumulated(83 * 60)
    }
}
