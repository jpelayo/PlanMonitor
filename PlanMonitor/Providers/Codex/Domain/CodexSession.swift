import Foundation

/// The ChatGPT browser session used for Codex usage. `cookieHeader` is the `Cookie:` header
/// value (`name=value; …`) captured at login or refreshed after a successful poll.
nonisolated struct CodexSession: VersionedCredentialPayload, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var cookieHeader: String
    /// Email when the profile has one, otherwise the display name.
    var identityLabel: String?
    var capturedAt: Date

    init(cookieHeader: String, identityLabel: String? = nil, capturedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.cookieHeader = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        self.identityLabel = identityLabel
        self.capturedAt = capturedAt
    }
}
