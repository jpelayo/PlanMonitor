import Foundation

/// The Claude browser session. `cookieHeader` is the full `Cookie:` header value captured at
/// login (`name=value; name=value`). Older builds stored either that header or the bare
/// `sessionKey` cookie value; both upgrade into this type.
nonisolated struct ClaudeSession: VersionedCredentialPayload, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var cookieHeader: String
    var email: String?
    var capturedAt: Date

    init(cookieHeader: String, email: String? = nil, capturedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.cookieHeader = Self.normalizedHeader(cookieHeader)
        self.email = email
        self.capturedAt = capturedAt
    }

    /// A legacy value without `=` is the bare session cookie value.
    static func normalizedHeader(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("=") ? trimmed : "sessionKey=\(trimmed)"
    }
}
