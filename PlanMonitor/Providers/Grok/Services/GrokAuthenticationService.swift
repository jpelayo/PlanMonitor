import Foundation

actor GrokAuthenticationService {
    enum RestoreResult: Sendable, Equatable {
        case absent
        case restored(email: String?)
        case unavailable
    }

    private let apiClient: GrokAPIClient
    private let oidcClient: GrokOIDCClient
    private let credentialStore: GrokCredentialStore
    /// Concurrent callers share one token exchange instead of racing auth.x.ai.
    private var refreshInFlight: Task<GrokCredentials, Error>?
    /// The newest credentials this run has seen, which outrank the Keychain. x.ai spends a refresh
    /// token on use (verified live, 2026-11-06), so once a refresh succeeds this is the only live
    /// copy until the Keychain accepts it. If the app quits before that, the next refresh fails
    /// and the user signs in again.
    private var latestCredentials: GrokCredentials?
    private var latestIsSaved = true

    init(
        apiClient: GrokAPIClient,
        oidcClient: GrokOIDCClient,
        credentialStore: GrokCredentialStore
    ) {
        self.apiClient = apiClient
        self.oidcClient = oidcClient
        self.credentialStore = credentialStore
    }

    func restoreStoredSession() async -> RestoreResult {
        switch await restoreOIDCCredentials() {
        case .unavailable:
            return .unavailable
        case .credentials(let credentials):
            return .restored(email: credentials.email)
        case .none:
            return .absent
        }
    }

    func startDeviceAuthorization() async throws -> GrokDeviceAuthorization {
        try await oidcClient.startDeviceAuthorization()
    }

    func completeDeviceAuthorization(_ authorization: GrokDeviceAuthorization) async throws -> GrokCredentials {
        let credentials = try await oidcClient.pollDeviceAuthorization(authorization)
        await adopt(credentials)
        // Cookies from the old sign-in flow: nothing reads them now.
        try? await credentialStore.deleteSession()
        return credentials
    }

    func refreshAccessTokenIfNeeded(force: Bool = false) async throws {
        await saveLatestIfNeeded()
        guard let credentials = try await currentCredentials() else {
            throw GrokAPIError.noAccessToken
        }
        if force || !credentials.isAccessTokenFresh() {
            do {
                await adopt(try await coalescedRefresh(of: credentials))
            } catch GrokOIDCError.invalidGrant {
                await forgetCredentials()
                throw GrokAPIError.noAccessToken
            }
        } else {
            await apiClient.setAccessToken(credentials.accessToken)
        }
    }

    func clearCredentials() async throws {
        latestCredentials = nil
        latestIsSaved = true
        try await credentialStore.deleteAll()
        await apiClient.setAccessToken(nil)
    }

    // MARK: - Private

    private enum OIDCRestore {
        case none
        case credentials(GrokCredentials)
        case unavailable
    }

    private func restoreOIDCCredentials() async -> OIDCRestore {
        await saveLatestIfNeeded()
        let stored: GrokCredentials?
        do {
            stored = try await currentCredentials()
        } catch {
            return .unavailable
        }
        guard let credentials = stored else { return .none }

        guard !credentials.isAccessTokenFresh() else {
            await apiClient.setAccessToken(credentials.accessToken)
            return .credentials(credentials)
        }
        do {
            let refreshed = try await coalescedRefresh(of: credentials)
            await adopt(refreshed)
            return .credentials(refreshed)
        } catch GrokOIDCError.invalidGrant {
            await forgetCredentials()
            return .none
        } catch {
            // Network trouble: keep the token we have and let the poll retry.
            await apiClient.setAccessToken(credentials.accessToken)
            return .credentials(credentials)
        }
    }

    /// Kept from the first read, so a Keychain that locks later cannot stop a running poll.
    private func currentCredentials() async throws -> GrokCredentials? {
        if let latestCredentials {
            return latestCredentials
        }
        latestCredentials = try await credentialStore.load()
        return latestCredentials
    }

    /// The token is in use from this moment, whether or not the Keychain takes it: a failed save
    /// is retried on the next cycle, never a reason to fall back to a spent token.
    private func adopt(_ credentials: GrokCredentials) async {
        latestCredentials = credentials
        latestIsSaved = false
        await apiClient.setAccessToken(credentials.accessToken)
        await saveLatestIfNeeded()
    }

    private func saveLatestIfNeeded() async {
        guard !latestIsSaved, let latestCredentials else { return }
        do {
            try await credentialStore.save(latestCredentials)
            latestIsSaved = true
        } catch {
            Task { @MainActor in AppRuntimeState.recordBreadcrumb("provider-grok-token-unsaved") }
        }
    }

    /// `invalid_grant` is definitive: the only deletion that is not an explicit sign-out.
    private func forgetCredentials() async {
        latestCredentials = nil
        latestIsSaved = true
        try? await credentialStore.delete()
        await apiClient.setAccessToken(nil)
    }

    private func coalescedRefresh(of credentials: GrokCredentials) async throws -> GrokCredentials {
        if let refreshInFlight {
            return try await refreshInFlight.value
        }
        // A caller that read its copy before another refresh finished holds a spent token, and
        // sending it would earn `invalid_grant` and delete good credentials.
        if let latestCredentials, latestCredentials.refreshToken != credentials.refreshToken {
            return latestCredentials
        }
        let task = Task { [oidcClient] in
            try await oidcClient.refresh(credentials: credentials)
        }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }
}
