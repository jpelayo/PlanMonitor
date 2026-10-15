import Foundation

/// Who is signed in, and which console org their billing comes from.
nonisolated struct ClaudePlatformAccount: Sendable, Equatable {
    let identityLabel: String
    let organizationID: String
    let organizationName: String?
}

/// Talks only to `ClaudePlatformCredentialStore`. The Codex shape — store the harvested cookies,
/// prove them against the identity endpoint, keep the rotated header current — with the console
/// org resolved at sign-in and remembered with the session, never hardcoded.
actor ClaudePlatformAuthenticationService {
    private let credentialStore: ClaudePlatformCredentialStore
    private let apiClient: ClaudePlatformClient

    init(credentialStore: ClaudePlatformCredentialStore, apiClient: ClaudePlatformClient) {
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    /// `.unavailable` is a locked or unreadable Keychain: transient, never a sign-out.
    func restoreStoredSession() async -> CredentialRestoreResult {
        do {
            guard let session = try await credentialStore.load() else { return .absent }
            await apiClient.setSessionCookies(session.cookieHeader)
            return .restored(identity: session.identityLabel)
        } catch {
            return .unavailable
        }
    }

    /// The org remembered with the session, if one was resolved before.
    func storedOrganizationID() async -> String? {
        try? await credentialStore.load()?.organizationID
    }

    /// Proves cookies harvested by the login window and only then stores them.
    ///
    /// The window offers cookies as soon as plausible ones appear, which is often before sign-in
    /// has finished, so most candidates fail. They are tried on a throwaway client: a failed
    /// candidate never reaches the Keychain and never replaces the session a running poll is using.
    func signIn(sessionCookies: String) async throws -> ClaudePlatformAccount {
        let probe = ClaudePlatformClient()
        await probe.setSessionCookies(sessionCookies)
        let account = try Self.account(from: await probe.fetchIdentity())
        let header = await probe.currentSessionCookies() ?? sessionCookies

        try await credentialStore.save(ClaudePlatformSession(
            cookieHeader: header,
            identityLabel: account.identityLabel,
            organizationID: account.organizationID,
            organizationName: account.organizationName
        ))
        await apiClient.setSessionCookies(header)
        return account
    }

    /// Re-reads identity and the console org for the stored session, and records both with it.
    func refreshAccount() async throws -> ClaudePlatformAccount {
        let account = try Self.account(from: await apiClient.fetchIdentity())
        await credentialStore.updateIdentity(
            label: account.identityLabel,
            organizationID: account.organizationID,
            organizationName: account.organizationName
        )
        return account
    }

    private static func account(from identity: ClaudePlatformIdentity) throws -> ClaudePlatformAccount {
        guard let organization = identity.preferredOrganization else {
            ClaudePlatformDiagnostics.log("no organization to read billing for — signed in, but nothing to show")
            throw ClaudePlatformClient.APIError.organizationUnavailable
        }
        let byCapability = organization.capabilities.contains { $0.lowercased() == "api" }
        ClaudePlatformDiagnostics.log(
            "using org \(ClaudePlatformDiagnostics.shortID(organization.id)) "
                + "'\(ClaudePlatformDiagnostics.scrubEmails(organization.name ?? "?"))' of \(identity.organizations.count), "
                + (byCapability ? "chosen for its `api` capability" : "chosen as the first — none says `api`")
        )
        guard let label = identity.email ?? organization.name else {
            ClaudePlatformDiagnostics.log("identity has neither an email nor an org name")
            throw IdentityError.malformedResponse
        }
        return ClaudePlatformAccount(
            identityLabel: label,
            organizationID: organization.id,
            organizationName: organization.name
        )
    }

    func clearCredentials() async throws {
        try await credentialStore.delete()
        await apiClient.clearSessionCookies()
    }

    /// Console sessions rotate cookies on successful calls; keep the stored copy current.
    func persistCurrentSessionCookiesIfNeeded() async {
        guard let currentCookies = await apiClient.currentSessionCookies(),
              !currentCookies.isEmpty else {
            return
        }
        await credentialStore.updateCookieHeader(currentCookies)
    }
}
