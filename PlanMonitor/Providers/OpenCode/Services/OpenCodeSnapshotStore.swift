import Foundation

nonisolated struct OpenCodePersistedSnapshot: Codable, Sendable {
    var schemaVersion: Int
    var providerID: ProviderID
    var snapshot: OpenCodeSnapshot
    var lastUpdated: Date
}

/// The last good poll, so a relaunch or re-enable shows figures at once and validates in the
/// background. Same shape as `ClaudePlatformSnapshotStore`, without a legacy list. Version 2 added
/// the Go windows (2026-10-22); a version-1 blob is simply not read — nothing had shipped.
struct OpenCodeSnapshotStore {
    static let schemaVersion = 2
    static let key = "opencode.persistedSnapshot.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` unless the stored blob is this version **and this provider's**. The provider check is
    /// what keeps a snapshot written under another provider's shape from ever being read as money.
    func load() -> OpenCodePersistedSnapshot? {
        guard let data = defaults.data(forKey: Self.key),
              let persisted = try? decoder.decode(OpenCodePersistedSnapshot.self, from: data),
              persisted.schemaVersion == Self.schemaVersion,
              persisted.providerID == .opencode else {
            return nil
        }
        return persisted
    }

    func save(snapshot: OpenCodeSnapshot, lastUpdated: Date) {
        guard !snapshot.isEmpty else {
            clear()
            return
        }
        let persisted = OpenCodePersistedSnapshot(
            schemaVersion: Self.schemaVersion,
            providerID: .opencode,
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
