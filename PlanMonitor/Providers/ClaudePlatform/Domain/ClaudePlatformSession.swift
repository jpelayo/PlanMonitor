import Foundation

/// The Claude Platform (`platform.claude.com`) browser session used for Claude-API. `cookieHeader`
/// is the `Cookie:` header value (`name=value; …`) harvested at login and kept current from the
/// `Set-Cookie` headers of later responses. The organization is the *console* org the session
/// reads billing for — discovered at login, never hardcoded.
nonisolated struct ClaudePlatformSession: VersionedCredentialPayload, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var cookieHeader: String
    /// The account email, when the identity endpoint reports one.
    var identityLabel: String?
    var organizationID: String?
    var organizationName: String?
    var capturedAt: Date

    init(
        cookieHeader: String,
        identityLabel: String? = nil,
        organizationID: String? = nil,
        organizationName: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.cookieHeader = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        self.identityLabel = identityLabel
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.capturedAt = capturedAt
    }
}
