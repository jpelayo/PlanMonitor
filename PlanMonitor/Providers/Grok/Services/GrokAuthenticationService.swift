import Foundation

actor GrokAuthenticationService {
    enum RestoreResult: Sendable, Equatable {
        case absent
        case restored(email: String?, hasUsageToken: Bool)
        case unavailable
    }

    private let apiClient: GrokAPIClient
    private let oidcClient: GrokOIDCClient
    private let credentialStore: GrokCredentialStore
    /// Concurrent callers share one token exchange instead of racing auth.x.ai.
    private var refreshInFlight: Task<GrokCredentials, Error>?

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
        let session: GrokWebSession?
        do {
            session = try await credentialStore.loadSession()
        } catch {
            return .unavailable
        }

        switch await restoreOIDCCredentials() {
        case .unavailable:
            return .unavailable
        case .credentials(let credentials):
            if let session, GrokWebViewCookieManager.cookieHeaderContainsSession(session.cookieHeader) {
                await apiClient.setSessionCookies(session.cookieHeader)
            }
            return .restored(email: credentials.email, hasUsageToken: true)
        case .none:
            break
        }

        guard let session else { return .absent }
        guard GrokWebViewCookieManager.cookieHeaderContainsSession(session.cookieHeader) else {
            try? await clearCredentials()
            return .absent
        }
        await apiClient.setSessionCookies(session.cookieHeader)
        return .restored(email: session.email, hasUsageToken: false)
    }

    func saveSessionCookies(_ sessionCookies: String) async throws {
        let existing = try? await credentialStore.loadSession()
        let stored = GrokWebSession(cookieHeader: sessionCookies, email: existing?.email, savedAt: Date())
        try await credentialStore.saveSession(stored)
        await apiClient.setSessionCookies(sessionCookies)
    }

    func storedCookies() async -> String? {
        guard let stored = try? await credentialStore.loadSession(),
              GrokWebViewCookieManager.cookieHeaderContainsSession(stored.cookieHeader) else {
            return nil
        }
        return stored.cookieHeader
    }

    func saveOIDCCredentials(_ credentials: GrokCredentials) async throws {
        try await credentialStore.save(credentials)
        await apiClient.setAccessToken(credentials.accessToken)
    }

    func startDeviceAuthorization() async throws -> GrokDeviceAuthorization {
        try await oidcClient.startDeviceAuthorization()
    }

    func completeDeviceAuthorization(
        _ authorization: GrokDeviceAuthorization,
        email: String?
    ) async throws -> GrokCredentials {
        let credentials = try await oidcClient.pollDeviceAuthorization(authorization, email: email)
        try await saveOIDCCredentials(credentials)
        return credentials
    }

    func refreshAccessTokenIfNeeded(force: Bool = false) async throws {
        guard let credentials = try await credentialStore.load() else {
            throw GrokAPIError.noAccessToken
        }
        if force || !credentials.isAccessTokenFresh() {
            do {
                let refreshed = try await coalescedRefresh(of: credentials)
                try await saveOIDCCredentials(refreshed)
            } catch GrokOIDCError.invalidGrant {
                try? await credentialStore.delete()
                await apiClient.setAccessToken(nil)
                throw GrokAPIError.noAccessToken
            }
        } else {
            await apiClient.setAccessToken(credentials.accessToken)
        }
    }

    func validateSession() async throws -> String {
        if let credentials = try? await credentialStore.load(), credentials.isAccessTokenFresh() {
            return credentials.email ?? String(localized: "Signed in")
        }
        let identity = try await apiClient.fetchIdentity()
        if var stored = try? await credentialStore.loadSession() {
            stored.email = identity
            stored.savedAt = Date()
            try? await credentialStore.saveSession(stored)
        }
        return identity
    }

    func clearCredentials() async throws {
        try await credentialStore.deleteAll()
        await apiClient.clearSessionCookies()
        await apiClient.setAccessToken(nil)
    }

    // MARK: - Private

    private enum OIDCRestore {
        case none
        case credentials(GrokCredentials)
        case unavailable
    }

    private func restoreOIDCCredentials() async -> OIDCRestore {
        let stored: GrokCredentials?
        do {
            stored = try await credentialStore.load()
        } catch {
            return .unavailable
        }
        guard var credentials = stored else { return .none }

        if !credentials.isAccessTokenFresh() {
            do {
                credentials = try await coalescedRefresh(of: credentials)
                try await credentialStore.save(credentials)
            } catch GrokOIDCError.invalidGrant {
                try? await credentialStore.delete()
                return .none
            } catch {
                // Network trouble: keep the token we have and let the poll retry.
                await apiClient.setAccessToken(credentials.accessToken)
                return .credentials(credentials)
            }
        }
        await apiClient.setAccessToken(credentials.accessToken)
        return .credentials(credentials)
    }

    private func coalescedRefresh(of credentials: GrokCredentials) async throws -> GrokCredentials {
        if let refreshInFlight {
            return try await refreshInFlight.value
        }
        let task = Task { [oidcClient] in
            try await oidcClient.refresh(credentials: credentials)
        }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return try await task.value
    }
}
