import Foundation

/// Accessibility class requested for a stored secret. New items always use the device-only
/// class; the enum exists so a store can report what an existing item was created with.
nonisolated enum SecureStoreAccessibility: String, Sendable, Equatable {
    case afterFirstUnlock
    case afterFirstUnlockThisDeviceOnly
}

nonisolated struct SecureStoreItemAttributes: Sendable, Equatable {
    /// `nil` when the backend does not report it (the file-based login keychain on macOS
    /// does not expose an accessibility class).
    let accessibility: SecureStoreAccessibility?
    let label: String?
    let modifiedAt: Date?
}

/// Every failure a caller can meaningfully react to. `locked` is the important one: it means
/// the secret exists but cannot be read right now, and must never be treated as "signed out".
nonisolated enum SecureStoreError: Error, Sendable, Equatable {
    case notFound
    case locked
    case missingEntitlement
    case decodeFailed(account: String)
    case unexpected(OSStatus)
}

/// The one abstraction between provider credential stores and wherever secrets actually live.
/// The app uses `KeychainSecureStore`; tests, UI tests and reviewer mode use
/// `InMemorySecureStore`. Accounts are opaque strings owned by each provider's store.
nonisolated protocol SecureStore: Sendable {
    /// `nil` when no item exists. Throws `.locked` and friends; never throws for absence.
    func read(account: String) async throws -> Data?
    func write(
        account: String,
        data: Data,
        accessibility: SecureStoreAccessibility,
        label: String?
    ) async throws
    /// Succeeds silently when nothing is stored.
    func delete(account: String) async throws
    func attributes(account: String) async throws -> SecureStoreItemAttributes?
}
