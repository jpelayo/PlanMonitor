//
//  ClaudeAuthenticationService.swift
//  PlanTracker
//

import Foundation

actor ClaudeAuthenticationService {
    private let credentialStore: ClaudeCredentialStore
    private let apiClient: ClaudeAPIClient
    private let defaults: UserDefaults

    /// Where builds before the envelope kept the account email. Read once, folded into the
    /// stored session, then removed.
    private static let legacyCachedEmailKey = "auth.cachedAccountEmail"

    init(credentialStore: ClaudeCredentialStore, apiClient: ClaudeAPIClient, defaults: UserDefaults = .standard) {
        self.credentialStore = credentialStore
        self.apiClient = apiClient
        self.defaults = defaults
    }

    func checkStoredCredentials() async -> ClaudeAuthState {
        switch await restoreStoredSession() {
        case .absent:
            return .unauthenticated
        case .unavailable:
            return .restoring(email: nil)
        case .restored(let identity):
            do {
                let email = try await refreshCachedIdentity()
                return .authenticated(email: email)
            } catch ClaudeAPIClient.APIError.unauthorized, ClaudeAPIClient.APIError.forbidden {
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
            if session.email == nil, let legacyEmail = defaults.string(forKey: Self.legacyCachedEmailKey) {
                session.email = legacyEmail
                await credentialStore.updateEmail(legacyEmail)
                defaults.removeObject(forKey: Self.legacyCachedEmailKey)
            }
            await apiClient.setSessionKey(session.cookieHeader)
            return .restored(identity: session.email)
        } catch {
            return .unavailable
        }
    }

    func saveSessionKey(_ sessionKey: String) async throws {
        let session = ClaudeSession(cookieHeader: sessionKey)
        try await credentialStore.save(session)
        await apiClient.setSessionKey(session.cookieHeader)
    }

    func validateSession() async throws -> String {
        try await refreshCachedIdentity()
    }

    func refreshCachedIdentity() async throws -> String {
        let bootstrap = try await apiClient.fetchBootstrap()
        guard let email = bootstrap.account?.emailAddress else {
            throw IdentityError.malformedResponse
        }
        await credentialStore.updateEmail(email)
        return email
    }

    func clearCredentials() async throws {
        try await credentialStore.delete()
        await apiClient.clearSessionKey()
        defaults.removeObject(forKey: Self.legacyCachedEmailKey)
    }
}
