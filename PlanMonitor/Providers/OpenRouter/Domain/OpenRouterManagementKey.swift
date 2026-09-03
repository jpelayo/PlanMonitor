import Foundation

/// The OpenRouter management key. Stored only after `/key` confirmed it is a management key;
/// `keyLabel` is the truncated label OpenRouter reports, never derived from the key itself.
nonisolated struct OpenRouterManagementKey: VersionedCredentialPayload, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var key: String
    var keyLabel: String?
    var validatedAt: Date

    init(key: String, keyLabel: String? = nil, validatedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keyLabel = keyLabel
        self.validatedAt = validatedAt
    }
}
