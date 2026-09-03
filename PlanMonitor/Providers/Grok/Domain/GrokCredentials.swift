import Foundation

nonisolated struct GrokCredentials: Codable, Sendable, Equatable {
    var schemaVersion: Int
    var issuer: URL
    var clientID: String
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: Date
    var tokenType: String
    var scopes: [String]
    var userID: String?
    var principalID: String?
    var principalType: String?
    var teamID: String?
    var email: String?
    var displayName: String?
    var importedAt: Date
    var refreshedAt: Date?

    static let currentSchemaVersion = 1
    static let expectedIssuer = URL(string: "https://auth.x.ai")!
    static let expectedClientID = "b1a00492-073a-47ea-816f-4c329264a828"

    var identity: AccountIdentity {
        AccountIdentity(
            email: email,
            displayName: displayName,
            principalType: principalType,
            isPersonalAccount: (principalType ?? "User") == "User"
        )
    }

    func isAccessTokenFresh(now: Date = Date(), leeway: TimeInterval = 300) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(now) > leeway
    }
}
