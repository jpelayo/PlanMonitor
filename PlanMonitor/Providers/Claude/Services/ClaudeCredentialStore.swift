import Foundation

/// Owns exactly one Keychain account: `sessionKey`, the item every shipped Claude build has
/// used. It is read in whatever shape that build wrote it and upgraded to the envelope.
actor ClaudeCredentialStore {
    static let account = "sessionKey"

    private let store: CredentialStore<ClaudeSession>

    init(secureStore: any SecureStore) {
        store = CredentialStore<ClaudeSession>(
            store: secureStore,
            provider: .claude,
            kind: "session",
            account: Self.account,
            legacyDecoders: [
                CredentialStore<ClaudeSession>.rawString { ClaudeSession(cookieHeader: $0) }
            ],
            onUnreadable: { Task { @MainActor in AppRuntimeState.recordBreadcrumb("credential-claude-unreadable") } }
        )
    }

    func load() async throws -> ClaudeSession? {
        try await store.load()
    }

    func save(_ session: ClaudeSession) async throws {
        try await store.save(session)
    }

    /// Records the identity the API reported without touching the cookie.
    func updateEmail(_ email: String) async {
        guard var session = try? await store.load(), session.email != email else { return }
        session.email = email
        try? await store.save(session)
    }

    func delete() async throws {
        try await store.delete()
    }
}
