import Foundation

/// The same five states as `CodexAuthState`. `restoring` is what makes "a locked Keychain is
/// transient, not signed-out" expressible: the cached snapshot stays on screen while the stored
/// session is re-read or re-validated.
nonisolated enum ClaudePlatformAuthState: Sendable, Equatable {
    case unknown
    case unauthenticated
    case authenticating
    case restoring(email: String?)
    case authenticated(email: String)

    var isAuthenticated: Bool {
        switch self {
        case .restoring, .authenticated:
            return true
        default:
            return false
        }
    }

    var email: String? {
        switch self {
        case .restoring(let email):
            return email
        case .authenticated(let email):
            return email
        default:
            return nil
        }
    }
}
