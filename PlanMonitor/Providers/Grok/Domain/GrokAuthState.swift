import Foundation

nonisolated struct AccountIdentity: Equatable, Sendable {
    var email: String?
    var displayName: String?
    var principalType: String?
    var isPersonalAccount: Bool
}

nonisolated enum GrokAuthState: Equatable, Sendable {
    case unauthenticated
    case importing
    case restoring
    case refreshing
    case authenticated(AccountIdentity)
    case reimportRequired(String)
    case failed(String)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var showsUsage: Bool {
        switch self {
        case .authenticated, .reimportRequired, .refreshing:
            true
        default:
            false
        }
    }

    var email: String? {
        switch self {
        case .authenticated(let identity):
            identity.email
        default:
            nil
        }
    }
}
