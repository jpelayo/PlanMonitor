import Foundation

/// Owns exactly one Keychain account: `openrouter.managementKey`. The key lives only here
/// and in memory — never in UserDefaults, logs, snapshots, or any `Text` view. Validation
/// happens in the view model before `save` is ever called; this store does not talk to the
/// network.
actor OpenRouterCredentialStore {
    static let account = "openrouter.managementKey"

    private let store: CredentialStore<OpenRouterManagementKey>
    private var cached: OpenRouterManagementKey?

    init(secureStore: any SecureStore) {
        store = CredentialStore<OpenRouterManagementKey>(
            store: secureStore,
            provider: .openrouter,
            kind: "managementKey",
            account: Self.account,
            legacyDecoders: [
                CredentialStore<OpenRouterManagementKey>.rawString { OpenRouterManagementKey(key: $0) }
            ],
            onUnreadable: { Task { @MainActor in AppRuntimeState.recordBreadcrumb("credential-openrouter-unreadable") } }
        )
    }

    func save(_ credential: OpenRouterManagementKey) async throws {
        try await store.save(credential)
        cached = credential
    }

    func load() async throws -> OpenRouterManagementKey? {
        if let cached { return cached }
        guard let credential = try await store.load(), !credential.key.isEmpty else { return nil }
        cached = credential
        return credential
    }

    /// Deletes only PlanTracker's copy. The key remains valid at OpenRouter — the UI
    /// says so, because "disconnect" must not be mistaken for "revoke".
    func clear() async {
        cached = nil
        try? await store.delete()
    }

    func hasCredential() async -> Bool {
        (try? await load()) != nil
    }
}
