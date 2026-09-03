//
//  CodexAuthenticationService.swift
//  PlanTracker
//

import Foundation

actor CodexAuthenticationService {
    private let credentialStore: CodexCredentialStore
    private let apiClient: OpenAIAPIClient
    private let defaults: UserDefaults

    private static let legacyCachedEmailKey = "codex.auth.cachedAccountEmail"

    init(credentialStore: CodexCredentialStore, apiClient: OpenAIAPIClient, defaults: UserDefaults = .standard) {
        self.credentialStore = credentialStore
        self.apiClient = apiClient
        self.defaults = defaults
    }

    func checkStoredCredentials() async -> CodexAuthState {
        switch await restoreStoredSession() {
        case .absent:
            return .unauthenticated
        case .unavailable:
            return .restoring(email: nil)
        case .restored(let identity):
            do {
                let email = try await refreshCachedIdentity()
                return .authenticated(email: email)
            } catch OpenAIAPIClient.APIError.unauthorized, OpenAIAPIClient.APIError.forbidden {
                try? await clearCredentials()
                return .unauthenticated
            } catch {
                return .restoring(email: identity)
            }
        }
    }

    func restoreStoredSession() async -> CredentialRestoreResult {
        do {
            guard var session = try await credentialStore.load() else { return .absent }
            if session.identityLabel == nil, let legacy = defaults.string(forKey: Self.legacyCachedEmailKey) {
                session.identityLabel = legacy
                await credentialStore.updateIdentityLabel(legacy)
                defaults.removeObject(forKey: Self.legacyCachedEmailKey)
            }
            await apiClient.setSessionCookies(session.cookieHeader)
            return .restored(identity: session.identityLabel)
        } catch {
            return .unavailable
        }
    }

    func saveSessionCookies(_ sessionCookies: String) async throws {
        let session = CodexSession(cookieHeader: sessionCookies)
        try await credentialStore.save(session)
        await apiClient.setSessionCookies(session.cookieHeader)
    }

    func validateSession() async throws -> String {
        try await refreshCachedIdentity(forceRefresh: true)
    }

    func refreshCachedIdentity(forceRefresh: Bool = false) async throws -> String {
        let profile = try await apiClient.fetchMeProfile(forceRefresh: forceRefresh)
        guard let identity = profile.email ?? profile.displayName else {
            throw IdentityError.malformedResponse
        }
        await credentialStore.updateIdentityLabel(identity)
        return identity
    }

    func clearCredentials() async throws {
        try await credentialStore.delete()
        await apiClient.clearSessionCookies()
        defaults.removeObject(forKey: Self.legacyCachedEmailKey)
    }

    /// ChatGPT rotates cookies on successful calls; keep the stored copy current.
    func persistCurrentSessionCookiesIfNeeded() async {
        guard let currentCookies = await apiClient.currentSessionCookies(),
              !currentCookies.isEmpty else {
            return
        }
        await credentialStore.updateCookieHeader(currentCookies)
    }
}
