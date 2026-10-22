import Foundation

/// An OpenCode Console API key, `oc_sk_<id>_<secret>`. Stored only after the API accepted it.
nonisolated struct OpenCodeAPIKey: VersionedCredentialPayload, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var key: String
    var validatedAt: Date

    init(key: String, validatedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.validatedAt = validatedAt
    }

    /// The part of the key the console itself keeps showing after creation — `oc_sk_0123456789ab`
    /// — and the only key-derived string that may ever be displayed.
    var prefix: String? { Self.prefix(of: key) }

    static func prefix(of key: String) -> String? {
        let parts = key.split(separator: "_", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "oc", parts[1] == "sk",
              !parts[2].isEmpty, !parts[3].isEmpty else { return nil }
        return "oc_sk_\(parts[2])"
    }

    /// Shape only; whether the key works is the API's to say.
    static func looksValid(_ key: String) -> Bool {
        prefix(of: key) != nil && key.count > 20
    }
}
