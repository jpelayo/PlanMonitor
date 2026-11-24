import Foundation

nonisolated struct GoogleAIPersistedSnapshot: Codable, Sendable {
    var schemaVersion: Int
    var providerID: ProviderID
    var usage: GoogleAIUsage
    var lastUpdated: Date
}

/// The last good report, so a relaunch or re-enable shows figures at once. Same shape as
/// `OpenCodeSnapshotStore`, with the provider check that keeps another provider's blob unread.
struct GoogleAISnapshotStore {
    static let schemaVersion = 1
    static let key = "googleai.persistedSnapshot.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GoogleAIPersistedSnapshot? {
        guard let data = defaults.data(forKey: Self.key),
              let persisted = try? decoder.decode(GoogleAIPersistedSnapshot.self, from: data),
              persisted.schemaVersion == Self.schemaVersion,
              persisted.providerID == .googleai else {
            return nil
        }
        return persisted
    }

    func save(usage: GoogleAIUsage, lastUpdated: Date) {
        guard !usage.isEmpty else {
            clear()
            return
        }
        let persisted = GoogleAIPersistedSnapshot(
            schemaVersion: Self.schemaVersion,
            providerID: .googleai,
            usage: usage,
            lastUpdated: lastUpdated
        )
        guard let data = try? encoder.encode(persisted) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
