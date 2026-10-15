import Foundation
import SwiftUI

/// Claude-API: promotional credit, spend and auto-payment on the Anthropic console.
///
/// The session lifecycle is Codex's — a harvested browser session, validated against the identity
/// endpoint, its rotated cookies written back after every good poll — and the money presentation is
/// OpenRouter's: its own menu-bar display and ring, no remaining/used fan-out, no
/// `ExtraExpenditureLine`. There is no shared-jar cookie recovery: the login web view is
/// non-persistent, so there is nothing to recover from.
@MainActor
@Observable
final class ClaudePlatformViewModel {
    private(set) var authState: ClaudePlatformAuthState = .unknown
    private(set) var snapshot: ClaudePlatformSnapshot = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isDemoMode = false
    private(set) var systemStatus: ClaudePlatformSystemStatus = .degraded
    private(set) var statusSourceUpdatedAt: Date?
    private(set) var nextRefreshAt: Date?
    private(set) var organizationName: String?

    private let snapshotStore: ClaudePlatformSnapshotStore
    private var isRecoveringAuth = false
    private var lastAuthRecoveryAttemptAt: Date?
    private let authRecoveryCooldown: TimeInterval = 60
    private let credentialRetryDelay: TimeInterval = 60
    private let statusRefreshInterval: TimeInterval = 5 * 60
    private let statusSignalWindow: TimeInterval = 24 * 60 * 60
    private var isFetchingStatus = false
    private var lastStatusFetchAt: Date?

    var pollingIntervalMinutes: Int = 5 {
        didSet {
            let seconds = TimeInterval(pollingIntervalMinutes * 60)
            Task { await pollingService.setPollingInterval(seconds) }
        }
    }

    /// What the menu-bar item prints. Persisted under `claudeapi.menuBarDisplay` — never the bare
    /// `menuBarDisplay` key `HostMigration` moved to OpenRouter.
    var menuBarDisplay: ClaudePlatformMenuBarDisplay = .default {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: "claudeapi.menuBarDisplay") }
    }

    /// What fills the ring around the menu-bar glyph.
    var ringSource: ClaudePlatformRingSource = .off {
        didSet { defaults.set(ringSource.rawValue, forKey: "claudeapi.ringSource") }
    }

    /// How amounts carry their currency, in the menu bar and the dropdown alike.
    var currencyStyle: CurrencyStyle = .default {
        didSet { defaults.set(currencyStyle.rawValue, forKey: "claudeapi.currencyStyle") }
    }

    /// `MenuBarLabel.variableValue`: `nil` leaves the ring whole.
    var ringFill: Double? {
        guard authState.isAuthenticated else { return nil }
        return ringSource.fill(for: snapshot)
    }

    /// Something is missing or doubtful, but what is on screen is still right. Shown in orange
    /// above the footer.
    var degradedMessage: String? {
        guard authState.isAuthenticated, !snapshot.isEmpty else { return nil }
        if snapshot.currencyMismatch {
            return String(localized: "Credit is reported in more than one currency; amounts may be mislabelled.")
        }
        if snapshot.spendUsed != nil, snapshot.spendCeiling == nil {
            return String(localized: "The spend limit is unavailable right now.")
        }
        return nil
    }

    /// Three missed cycles in a row.
    var isStale: Bool {
        guard let lastUpdated, !isDemoMode else { return false }
        return Date().timeIntervalSince(lastUpdated) > TimeInterval(pollingIntervalMinutes * 60 * 3)
    }

    let sessionPreferences: SessionTrackingPreferences
    let sessionTracker: SessionTracker
    let menuBarText: MenuBarTextPreferences

    private let defaults: UserDefaults
    private let apiClient: ClaudePlatformClient
    private let authService: ClaudePlatformAuthenticationService
    private let pollingService: ClaudePlatformPollingService
    private let statusService: ClaudePlatformStatusService

    private var identityTask: Task<Void, Never>?
    private var cookiePersistTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var credentialRetryTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    init(
        secureStore: any SecureStore,
        defaults: UserDefaults = .standard,
        apiClient: ClaudePlatformClient = ClaudePlatformClient()
    ) {
        self.defaults = defaults
        self.apiClient = apiClient
        self.authService = ClaudePlatformAuthenticationService(
            credentialStore: ClaudePlatformCredentialStore(secureStore: secureStore),
            apiClient: apiClient
        )
        self.pollingService = ClaudePlatformPollingService(apiClient: apiClient)
        self.statusService = ClaudePlatformStatusService()
        self.snapshotStore = ClaudePlatformSnapshotStore(defaults: defaults)
        self.sessionPreferences = SessionTrackingPreferences(namespace: "claudeapi", defaults: defaults)
        self.sessionTracker = SessionTracker(namespace: "claudeapi", defaults: defaults)
        self.menuBarText = MenuBarTextPreferences(namespace: "claudeapi", defaults: defaults)

        // Direct assignment in `init` does not run `didSet`, so restored values are not written back.
        if let raw = defaults.string(forKey: "claudeapi.menuBarDisplay"),
           let display = ClaudePlatformMenuBarDisplay(rawValue: raw) {
            menuBarDisplay = display
        }
        if let raw = defaults.string(forKey: "claudeapi.ringSource"),
           let source = ClaudePlatformRingSource(rawValue: raw) {
            ringSource = source
        }
        if let raw = defaults.string(forKey: "claudeapi.currencyStyle"),
           let style = CurrencyStyle(rawValue: raw) {
            currencyStyle = style
        }

        restorePersistedSnapshot()
        setupPollingCallbacks()
    }

    /// Captures `self` weakly in the outer task as well — the inner closures' `[weak self]` would
    /// otherwise sit inside an implicit strong capture (the `ImplicitStrongCapture` warning the
    /// other view models still carry).
    private func setupPollingCallbacks() {
        Task { [weak self, pollingService] in
            guard self != nil else { return }
            await pollingService.setCallbacks(
                onUpdate: { [weak self] snapshot in
                    Task { @MainActor [weak self] in
                        self?.apply(snapshot)
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

    private func apply(_ newSnapshot: ClaudePlatformSnapshot) {
        guard !isDemoMode else { return }
        let changed = snapshot != newSnapshot
        snapshot = newSnapshot
        lastUpdated = Date()
        errorMessage = nil
        if sessionPreferences.isEnabled {
            // Increasing counters only — never a remaining balance.
            let promoConsumed = newSnapshot.promoGranted.flatMap { granted in
                newSnapshot.promoRemaining.map { granted - $0 }
            }
            sessionTracker.processTick(
                signals: [
                    .minorUnits("spend", newSnapshot.spendUsed),
                    .minorUnits("promoConsumed", promoConsumed),
                    .minorUnits("invoice", newSnapshot.pendingInvoice)
                ].compactMap { $0 },
                minInterval: sessionPreferences.checkInterval,
                resetHour: sessionPreferences.resetHour
            )
        }
        if changed {
            persistSnapshot()
        }
        cookiePersistTask?.cancel()
        cookiePersistTask = Task { [weak self] in
            await self?.authService.persistCurrentSessionCookiesIfNeeded()
        }
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            await self?.refreshStatus(force: false)
        }
    }

    // MARK: - Authentication

    func checkAuthentication() async {
        guard !isDemoMode else { return }
        isLoading = true
        authState = .unknown
        AppRuntimeState.recordBreadcrumb("provider-claudeapi-check-authentication")

        switch await authService.restoreStoredSession() {
        case .restored(let identity):
            AppRuntimeState.recordBreadcrumb("provider-claudeapi-auth-restored-keychain")
            authState = .restoring(email: identity)
            errorMessage = nil
            // With the org already known, polling starts from the Keychain alone; otherwise it
            // waits for the identity refresh below to resolve one.
            let storedOrganizationID = await authService.storedOrganizationID()
            if let storedOrganizationID {
                await pollingService.setOrganizationID(storedOrganizationID)
                await startPolling()
            }
            isLoading = false
            identityTask?.cancel()
            identityTask = Task { [weak self] in
                await self?.refreshRestoredIdentity(startPolling: storedOrganizationID == nil)
            }
            return
        case .unavailable:
            AppRuntimeState.recordBreadcrumb("provider-claudeapi-auth-keychain-unavailable")
            authState = .restoring(email: nil)
            isLoading = false
            scheduleCredentialRetry()
            return
        case .absent:
            break
        }

        AppRuntimeState.recordBreadcrumb("provider-claudeapi-auth-missing")
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

    private func refreshRestoredIdentity(startPolling shouldStartPolling: Bool) async {
        do {
            let account = try await authService.refreshAccount()
            guard authState.isAuthenticated, !Task.isCancelled else { return }
            AppRuntimeState.recordBreadcrumb("provider-claudeapi-auth-identity-refreshed")
            adopt(account)
            await pollingService.setOrganizationID(account.organizationID)
            if shouldStartPolling {
                await startPolling()
            }
            await authService.persistCurrentSessionCookiesIfNeeded()
        } catch let error as ClaudePlatformClient.APIError {
            switch error {
            case .unauthorized, .forbidden, .organizationUnavailable:
                handleError(error)
            default:
                break
            }
        } catch {
            // Malformed or transient: keep the restored state.
        }
    }

    /// The login window's callback. `false` means "not signed in yet" and the window stays open:
    /// it offers cookies before sign-in has finished, so a rejection here is routine and leaves
    /// the provider's state — and any session already stored — exactly as it was.
    func handleLoginSuccess(sessionCookies: String) async -> Bool {
        do {
            let account = try await authService.signIn(sessionCookies: sessionCookies)
            AppRuntimeState.recordBreadcrumb("provider-claudeapi-login-success")
            isDemoMode = false
            errorMessage = nil
            adopt(account)
            await pollingService.setOrganizationID(account.organizationID)
            await startPolling()
            return true
        } catch ClaudePlatformClient.APIError.organizationUnavailable {
            // Signed in, but to an account with no console org: worth saying, once.
            errorMessage = ClaudePlatformClient.APIError.organizationUnavailable.errorDescription
            return false
        } catch {
            ClaudePlatformDiagnostics.log("candidate not a session: \(error.localizedDescription)")
            return false
        }
    }

    private func adopt(_ account: ClaudePlatformAccount) {
        authState = .authenticated(email: account.identityLabel)
        organizationName = account.organizationName
    }

    func logout() async {
        AppRuntimeState.recordBreadcrumb("provider-claudeapi-logout")
        cancelBackgroundWork()
        await pollingService.stopPolling()
        await pollingService.resetSteadyState()
        try? await authService.clearCredentials()

        authState = .unauthenticated
        snapshot = .empty
        lastUpdated = nil
        errorMessage = nil
        organizationName = nil
        isDemoMode = false
        snapshotStore.clear()
        CacheJanitor.cleanupTransientCaches(reason: "claudeapi-logout")
    }

    func refreshUsage() async {
        guard authState.isAuthenticated, !isDemoMode, !isLoading else { return }
        AppRuntimeState.recordBreadcrumb("provider-claudeapi-manual-refresh")
        isLoading = true
        await pollingService.fetchSnapshot(forceMetadataRefresh: true)
        // The manual fetch just did this cycle's work, so restart the pending sleep: the next
        // automatic poll is a full interval away and the footer countdown says so.
        await pollingService.restartCycle()
        await refreshStatus(force: true)
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
        statusTask?.cancel()
        identityTask = nil
        cookiePersistTask = nil
        recoveryTask = nil
        credentialRetryTask = nil
        statusTask = nil
    }

    private func startPolling() async {
        AppRuntimeState.recordBreadcrumb("provider-claudeapi-poll-start")
        let interval = TimeInterval(pollingIntervalMinutes * 60)
        await pollingService.setPollingInterval(interval)
        await pollingService.startPolling()
        await refreshStatus(force: true)
    }

    // MARK: - Status pill

    var displayedSystemStatus: ClaudePlatformSystemStatus {
        visibleSystemStatus ?? .operational
    }

    var visibleSystemStatus: ClaudePlatformSystemStatus? {
        guard let sourceUpdatedAt = statusSourceUpdatedAt, isUsableStatusTimestamp(sourceUpdatedAt) else {
            return nil
        }
        switch systemStatus {
        case .operational:
            return nil
        case .degraded, .outage:
            return systemStatus
        }
    }

    private func refreshStatus(force: Bool) async {
        guard !isDemoMode else { return }
        let now = Date()
        if !force,
           let lastFetch = lastStatusFetchAt,
           now.timeIntervalSince(lastFetch) < statusRefreshInterval {
            return
        }

        guard !isFetchingStatus else { return }
        isFetchingStatus = true
        lastStatusFetchAt = now
        defer { isFetchingStatus = false }

        do {
            let status = try await statusService.fetchStatus()
            guard !Task.isCancelled else { return }
            systemStatus = status.status
            // Dated by when we fetched it, not by `page.updated_at`, which moves backwards when an
            // incident clears — see `CodexUsageViewModel.refreshCodexStatus`.
            statusSourceUpdatedAt = status.fetchedAt
        } catch {
            // Keep the previous status on transient failures.
        }
    }

    private func isUsableStatusTimestamp(_ sourceUpdatedAt: Date) -> Bool {
        let now = Date()
        if sourceUpdatedAt > now.addingTimeInterval(120) {
            return false
        }
        return now.timeIntervalSince(sourceUpdatedAt) <= statusSignalWindow
    }

    var dailySessionFormatted: String? {
        guard sessionPreferences.isEnabled else { return nil }
        return SessionTimeFormatter.line(totalSeconds: sessionTracker.totalSeconds)
    }

    // MARK: - Errors

    private func handleError(_ error: Error) {
        ClaudePlatformDiagnostics.log("error: \(error.localizedDescription)")
        if let apiError = error as? ClaudePlatformClient.APIError {
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

    /// A billing call said no. Ask the identity endpoint — the only source allowed to sign
    /// anyone out — before believing it.
    private func recoverFromAuthorizationFailure(_ apiError: ClaudePlatformClient.APIError) async {
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

        AppRuntimeState.recordBreadcrumb("provider-claudeapi-auth-recovery-start")

        let outcome = await recoverUsingStoredSession()
        ClaudePlatformDiagnostics.log("recovery after \(apiError.errorDescription ?? "an auth error"): \(outcome)")
        switch outcome {
        case .recovered:
            AppRuntimeState.recordBreadcrumb("provider-claudeapi-auth-recovery-stored-session")
            errorMessage = nil
        case .rejected:
            // The identity endpoint itself said no: the session is over. Credentials stay until
            // the user signs out or in again, as for every provider.
            AppRuntimeState.recordBreadcrumb("provider-claudeapi-auth-recovery-rejected")
            authState = .unauthenticated
            await pollingService.stopPolling()
            nextRefreshAt = nil
            errorMessage = apiError.errorDescription
        case .inconclusive:
            // Network, a locked Keychain, an odd body: transient. Keep what is on screen.
            AppRuntimeState.recordBreadcrumb("provider-claudeapi-auth-recovery-failed")
            if !authState.isAuthenticated {
                authState = .unauthenticated
            }
            errorMessage = apiError.errorDescription
        }
    }

    private enum RecoveryOutcome {
        case recovered
        /// No stored session, or the identity endpoint answered 401/403.
        case rejected
        case inconclusive
    }

    private var canAttemptAuthRecovery: Bool {
        guard !isRecoveringAuth else { return false }
        guard let lastAttempt = lastAuthRecoveryAttemptAt else { return true }
        return Date().timeIntervalSince(lastAttempt) >= authRecoveryCooldown
    }

    private func recoverUsingStoredSession() async -> RecoveryOutcome {
        let identity: String?
        switch await authService.restoreStoredSession() {
        case .restored(let label): identity = label
        case .absent: return .rejected
        case .unavailable: return .inconclusive
        }

        if let identity, !authState.isAuthenticated {
            authState = .restoring(email: identity)
        }

        do {
            let account = try await authService.refreshAccount()
            adopt(account)
            await pollingService.setOrganizationID(account.organizationID)
            await authService.persistCurrentSessionCookiesIfNeeded()
            return .recovered
        } catch ClaudePlatformClient.APIError.unauthorized, ClaudePlatformClient.APIError.forbidden {
            return .rejected
        } catch {
            return .inconclusive
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
        return snapshot.isEmpty && lastUpdated == nil
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) async {
        guard authState.isAuthenticated else { return }
        await pollingService.handleMemoryPressure(level)
    }

    // MARK: - Snapshot persistence

    private func restorePersistedSnapshot() {
        guard let persisted = snapshotStore.load() else { return }
        snapshot = persisted.snapshot
        lastUpdated = persisted.lastUpdated
        AppRuntimeState.recordBreadcrumb("provider-claudeapi-snapshot-restored")
    }

    private func persistSnapshot() {
        guard !isDemoMode, let lastUpdated else { return }
        snapshotStore.save(snapshot: snapshot, lastUpdated: lastUpdated)
    }
}

// MARK: - Reviewer mode

extension ClaudePlatformViewModel: DemoCapable {
    func enterDemo() {
        guard !isDemoMode else { return }
        isDemoMode = true
        cancelBackgroundWork()
        Task { await pollingService.stopPolling() }
        nextRefreshAt = nil
        authState = .authenticated(email: ClaudePlatformDemoSnapshot.identityLabel)
        organizationName = ClaudePlatformDemoSnapshot.organizationName

        let now = Date()
        snapshot = ClaudePlatformDemoSnapshot.snapshot(now: now)
        lastUpdated = now
        errorMessage = nil
        systemStatus = .operational
        statusSourceUpdatedAt = now
        sessionTracker.setMockAccumulated(83 * 60) // 1h 23m
    }
}
