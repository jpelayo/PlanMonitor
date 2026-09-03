import Foundation

nonisolated struct StoredSnapshot: Codable, Sendable {
    var schemaVersion: Int
    var providerID: ProviderID?
    var snapshot: OpenRouterSnapshot
    var lastSuccess: Date
}

/// Persists the sanitized snapshot so the menu bar has something to show at launch.
/// Contains no management key, tokens, or user ids — see the domain model.
struct OpenRouterSnapshotStore {
    private let key = "openrouter.persistedBudgetSnapshot.v1"
    private let legacyKey = "openRouterSnapshot"
    private let schemaVersion = 1
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> StoredSnapshot? {
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
           stored.schemaVersion == schemaVersion,
           stored.providerID ?? .openrouter == .openrouter {
            return stored
        }

        // The legacy key is copied forward and left in place until sign-out.
        guard let data = defaults.data(forKey: legacyKey),
              let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
              stored.schemaVersion == schemaVersion else {
            return nil
        }
        save(stored.snapshot, at: stored.lastSuccess)
        return stored
    }

    func save(_ snapshot: OpenRouterSnapshot, at date: Date) {
        let stored = StoredSnapshot(
            schemaVersion: schemaVersion,
            providerID: .openrouter,
            snapshot: snapshot,
            lastSuccess: date
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: legacyKey)
    }
}
