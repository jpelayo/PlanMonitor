import Foundation

nonisolated struct ClaudePlatformPersistedSnapshot: Codable, Sendable {
    var schemaVersion: Int
    var providerID: ProviderID
    var snapshot: ClaudePlatformSnapshot
    var lastUpdated: Date
}

/// The last good poll, so a relaunch or re-enable shows figures at once and validates in the
/// background. Same shape as `GrokUsageSnapshotStore`, without a legacy list — nothing older exists.
struct ClaudePlatformSnapshotStore {
    static let schemaVersion = 1
    static let key = "claudeapi.persistedSnapshot.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` unless the stored blob is this version **and this provider's**. The provider check is
    /// what keeps a snapshot written under another provider's shape from ever being read as money.
    func load() -> ClaudePlatformPersistedSnapshot? {
        guard let data = defaults.data(forKey: Self.key),
              let persisted = try? decoder.decode(ClaudePlatformPersistedSnapshot.self, from: data),
              persisted.schemaVersion == Self.schemaVersion,
              persisted.providerID == .claudeapi else {
            return nil
        }
        return persisted
    }

    func save(snapshot: ClaudePlatformSnapshot, lastUpdated: Date) {
        guard !snapshot.isEmpty else {
            clear()
            return
        }
        let persisted = ClaudePlatformPersistedSnapshot(
            schemaVersion: Self.schemaVersion,
            providerID: .claudeapi,
            snapshot: snapshot,
            lastUpdated: lastUpdated
        )
        guard let data = try? encoder.encode(persisted) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
