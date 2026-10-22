import Foundation

/// A Console API key has no refresh cycle and no session, so there is nothing between connected
/// and rejected: a 401 means revoked or expired, a 403 a key without Budgets › Read.
nonisolated enum OpenCodeConnectionState: Equatable, Sendable {
    case disconnected
    case validating
    case connected(keyPrefix: String)
    /// The API rejected the stored key. The last snapshot stays visible, marked stale, and the key
    /// stays stored until the user replaces or removes it.
    case invalidKey(keyPrefix: String, reason: String)

    /// Whether budget data should be shown.
    var showsBudget: Bool {
        switch self {
        case .connected, .invalidKey: true
        case .disconnected, .validating: false
        }
    }

    var keyPrefix: String? {
        switch self {
        case .connected(let prefix), .invalidKey(let prefix, _): prefix
        case .disconnected, .validating: nil
        }
    }
}
