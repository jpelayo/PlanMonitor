import Foundation

nonisolated struct GrokUsageSnapshot: Codable, Sendable {
    var schemaVersion: Int
    var providerID: ProviderID
    var usage: GrokUsageData
    var lastSuccess: Date
}

/// The pre-provider-tagged shape (`schemaVersion` 1, no `providerID`).
private nonisolated struct LegacyGrokUsageSnapshot: Decodable {
    var schemaVersion: Int
    var usage: GrokUsageData
    var lastSuccess: Date
}

struct GrokUsageSnapshotStore {
    static let schemaVersion = 2
    private let key = "grok.persistedUsageSnapshot.v2"
    private let legacyKeys = ["grok.persistedUsageSnapshot.v1", "grokUsageSnapshot"]
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GrokUsageSnapshot? {
        if let data = defaults.data(forKey: key),
           let snapshot = try? decoder.decode(GrokUsageSnapshot.self, from: data),
           snapshot.schemaVersion == Self.schemaVersion,
           snapshot.providerID == .grok {
            return snapshot
        }

        // Legacy keys are read and copied forward but left in place until sign-out.
        for legacyKey in legacyKeys {
            guard let data = defaults.data(forKey: legacyKey),
                  let legacy = try? decoder.decode(LegacyGrokUsageSnapshot.self, from: data) else {
                continue
            }
            let migrated = GrokUsageSnapshot(
                schemaVersion: Self.schemaVersion,
                providerID: .grok,
                usage: legacy.usage,
                lastSuccess: legacy.lastSuccess
            )
            if let migratedData = try? encoder.encode(migrated) {
                defaults.set(migratedData, forKey: key)
            }
            return migrated
        }
        return nil
    }

    func save(usage: GrokUsageData, lastSuccess: Date) {
        let snapshot = GrokUsageSnapshot(
            schemaVersion: Self.schemaVersion,
            providerID: .grok,
            usage: usage,
            lastSuccess: lastSuccess
        )
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
        for legacyKey in legacyKeys {
            defaults.removeObject(forKey: legacyKey)
        }
    }
}
