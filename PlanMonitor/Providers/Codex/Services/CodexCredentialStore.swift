import Foundation

/// Owns exactly one Keychain account: `codex.session`. Earlier unified builds wrote the bare
/// cookie header there; it upgrades to the envelope on first read.
actor CodexCredentialStore {
    static let account = "codex.session"

    private let store: CredentialStore<CodexSession>

    init(secureStore: any SecureStore) {
        store = CredentialStore<CodexSession>(
            store: secureStore,
            provider: .codex,
            kind: "session",
            account: Self.account,
            legacyDecoders: [
                CredentialStore<CodexSession>.rawString { CodexSession(cookieHeader: $0) }
            ],
            onUnreadable: { Task { @MainActor in AppRuntimeState.recordBreadcrumb("credential-codex-unreadable") } }
        )
    }

    func load() async throws -> CodexSession? {
        try await store.load()
    }

    func save(_ session: CodexSession) async throws {
        try await store.save(session)
    }

    func updateIdentityLabel(_ label: String) async {
        guard var session = try? await store.load(), session.identityLabel != label else { return }
        session.identityLabel = label
        try? await store.save(session)
    }

    /// Persists rotated cookies while keeping the identity already recorded.
    func updateCookieHeader(_ header: String) async {
        guard var session = try? await store.load(), session.cookieHeader != header else { return }
        session.cookieHeader = header
        session.capturedAt = Date()
        try? await store.save(session)
    }

    func delete() async throws {
        try await store.delete()
    }
}
