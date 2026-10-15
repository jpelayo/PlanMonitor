import Foundation

/// Owns exactly one Keychain account: `claudeapi.session`. Never `sessionKey` — that unnamespaced
/// account is Claude's, kept for App Store continuity, and writing it would sign Claude out.
/// Nothing has ever shipped under this name, so there are no legacy shapes to decode.
actor ClaudePlatformCredentialStore {
    static let account = "claudeapi.session"

    private let store: CredentialStore<ClaudePlatformSession>

    init(secureStore: any SecureStore) {
        store = CredentialStore<ClaudePlatformSession>(
            store: secureStore,
            provider: .claudeapi,
            kind: "session",
            account: Self.account,
            onUnreadable: { Task { @MainActor in AppRuntimeState.recordBreadcrumb("credential-claudeapi-unreadable") } }
        )
    }

    func load() async throws -> ClaudePlatformSession? {
        try await store.load()
    }

    func save(_ session: ClaudePlatformSession) async throws {
        try await store.save(session)
    }

    /// Records who the session belongs to and which console org it reads.
    func updateIdentity(label: String?, organizationID: String?, organizationName: String?) async {
        guard var session = try? await store.load() else { return }
        let changed = session.identityLabel != label
            || session.organizationID != organizationID
            || session.organizationName != organizationName
        guard changed else { return }
        session.identityLabel = label
        session.organizationID = organizationID
        session.organizationName = organizationName
        try? await store.save(session)
    }

    /// Persists rotated cookies while keeping the identity already recorded.
    func updateCookieHeader(_ header: String) async {
        guard var session = try? await store.load(), session.cookieHeader != header else { return }
        ClaudePlatformDiagnostics.log(
            "session cookies rotated; saving \(ClaudePlatformDiagnostics.names(inHeader: header)) "
                + "(was \(ClaudePlatformDiagnostics.names(inHeader: session.cookieHeader)))"
        )
        session.cookieHeader = header
        session.capturedAt = Date()
        try? await store.save(session)
    }

    func delete() async throws {
        try await store.delete()
    }
}
