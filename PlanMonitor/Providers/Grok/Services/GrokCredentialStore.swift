import Foundation

/// Owns the two Grok Keychain accounts and nothing else:
/// - `grok.session`     — the web cookie session (`GrokWebSession`)
/// - `grok.credentials` — the OIDC token envelope (`GrokCredentials`)
/// Both read every shape an older build could have written (bare JSON under the current
/// accounts, raw cookies under `grokSessionCookies`, bare JSON under `grokCredentials`) and
/// upgrade in place.
actor GrokCredentialStore {
    static let sessionAccount = "grok.session"
    static let credentialsAccount = "grok.credentials"
    static let legacySessionAccount = "grokSessionCookies"
    static let legacyCredentialsAccount = "grokCredentials"

    private let session: CredentialStore<GrokWebSession>
    private let credentials: CredentialStore<GrokCredentials>

    init(secureStore: any SecureStore) {
        let legacySession = CredentialStore<GrokWebSession>.bareJSON(
            LegacyStoredGrokSession.self,
            dates: .deferredToDate
        ) { legacy in
            GrokWebSession(cookieHeader: legacy.cookies, email: legacy.email, savedAt: legacy.savedAt)
        }
        let rawCookies = CredentialStore<GrokWebSession>.rawString { GrokWebSession(cookieHeader: $0) }
        session = CredentialStore<GrokWebSession>(
            store: secureStore,
            provider: .grok,
            kind: "session",
            account: Self.sessionAccount,
            legacyDecoders: [legacySession, rawCookies],
            legacyAccounts: [.init(Self.legacySessionAccount, decoders: [rawCookies])],
            onUnreadable: { Task { @MainActor in AppRuntimeState.recordBreadcrumb("credential-grok-session-unreadable") } }
        )

        let bareCredentials = CredentialStore<GrokCredentials>.bareJSON(GrokCredentials.self) { $0 }
        credentials = CredentialStore<GrokCredentials>(
            store: secureStore,
            provider: .grok,
            kind: "oidc",
            account: Self.credentialsAccount,
            legacyDecoders: [bareCredentials],
            legacyAccounts: [.init(Self.legacyCredentialsAccount, decoders: [bareCredentials])],
            onUnreadable: { Task { @MainActor in AppRuntimeState.recordBreadcrumb("credential-grok-oidc-unreadable") } }
        )
    }

    // MARK: Web session

    func loadSession() async throws -> GrokWebSession? {
        try await session.load()
    }

    func saveSession(_ value: GrokWebSession) async throws {
        try await session.save(value)
    }

    func deleteSession() async throws {
        try await session.delete()
    }

    // MARK: OIDC credentials

    func load() async throws -> GrokCredentials? {
        guard let stored = try await credentials.load() else { return nil }
        guard stored.schemaVersion <= GrokCredentials.currentSchemaVersion else { return nil }
        return stored
    }

    func save(_ value: GrokCredentials) async throws {
        try await credentials.save(value)
    }

    func delete() async throws {
        try await credentials.delete()
    }

    /// Sign-out: both accounts and every legacy name.
    func deleteAll() async throws {
        try await session.delete()
        try await credentials.delete()
    }
}
