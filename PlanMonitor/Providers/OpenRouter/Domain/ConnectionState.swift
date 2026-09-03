import Foundation

nonisolated struct KeyIdentity: Codable, Equatable, Sendable {
    /// The API-provided truncated key (`sk-or-v1-au7...890`). The only key-derived
    /// string that may ever be displayed.
    var label: String
    var isManagementKey: Bool
    var isFreeTier: Bool
    var expiresAt: Date?
}

/// Four states. A management key has no refresh cycle and no session, so there is no
/// `.refreshing` or `.reimportRequired` equivalent: a 401 means revoked or wrong.
nonisolated enum ConnectionState: Equatable, Sendable {
    case disconnected
    case validating
    case connected(KeyIdentity)
    case invalidKey(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Whether budget data should be shown. An invalid key keeps the last snapshot
    /// visible (marked stale) rather than blanking the popover.
    var showsBudgets: Bool {
        switch self {
        case .connected, .invalidKey: true
        case .disconnected, .validating: false
        }
    }

    var identity: KeyIdentity? {
        if case .connected(let identity) = self { return identity }
        return nil
    }
}
