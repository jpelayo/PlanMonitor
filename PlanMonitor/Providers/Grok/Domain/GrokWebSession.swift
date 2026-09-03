import Foundation

/// The grok.com browser session (`sso` / `sso-rw` cookies) captured by the login window. It
/// is the bridge to the OIDC device flow and a fallback identity source; the usage API itself
/// runs on `GrokCredentials`.
nonisolated struct GrokWebSession: VersionedCredentialPayload, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var cookieHeader: String
    var email: String?
    var savedAt: Date

    init(cookieHeader: String, email: String? = nil, savedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.cookieHeader = cookieHeader
        self.email = email
        self.savedAt = savedAt
    }
}

/// The shape the previous build wrote under `grok.session` (bare JSON, default date encoding).
/// Kept only so it can be decoded and upgraded.
nonisolated struct LegacyStoredGrokSession: Decodable {
    var cookies: String
    var email: String?
    var savedAt: Date
}

extension GrokCredentials: VersionedCredentialPayload {}
