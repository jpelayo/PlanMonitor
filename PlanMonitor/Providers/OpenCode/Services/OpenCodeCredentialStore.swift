import Foundation

/// Owns exactly one Keychain account: `opencode.apiKey`. The key lives only here and in memory —
/// never in UserDefaults, logs, snapshots, or any `Text` view. Validation happens in the view
/// model before `save` is ever called; this store does not talk to the network. Nothing has ever
/// shipped under this name, so there are no legacy shapes to decode.
actor OpenCodeCredentialStore {
    static let account = "opencode.apiKey"

    private let store: CredentialStore<OpenCodeAPIKey>
    private var cached: OpenCodeAPIKey?

    init(secureStore: any SecureStore) {
        store = CredentialStore<OpenCodeAPIKey>(
            store: secureStore,
            provider: .opencode,
            kind: "apiKey",
            account: Self.account,
            onUnreadable: { Task { @MainActor in AppRuntimeState.recordBreadcrumb("credential-opencode-unreadable") } }
        )
    }

    func save(_ credential: OpenCodeAPIKey) async throws {
        try await store.save(credential)
        cached = credential
    }

    func load() async throws -> OpenCodeAPIKey? {
        if let cached { return cached }
        guard let credential = try await store.load(), !credential.key.isEmpty else { return nil }
        cached = credential
        return credential
    }

    /// Deletes only PlanMonitor's copy. The key stays valid in the OpenCode Console — the UI says
    /// so, because "remove" must not be mistaken for "revoke".
    func clear() async {
        cached = nil
        try? await store.delete()
    }
}
