import Foundation

/// Process-local secret storage. Used whenever the app must not reach the user's Keychain:
/// the unit-test host, UI tests, and reviewer mode. Nothing survives the process.
actor InMemorySecureStore: SecureStore {
    private struct Item {
        var data: Data
        var accessibility: SecureStoreAccessibility
        var label: String?
        var modifiedAt: Date
    }

    private var items: [String: Item] = [:]
    /// When set, every read throws `.locked`. Lets tests prove a locked keychain is transient.
    private var isLocked = false

    init() {}

    func read(account: String) async throws -> Data? {
        if isLocked { throw SecureStoreError.locked }
        return items[account]?.data
    }

    func write(
        account: String,
        data: Data,
        accessibility: SecureStoreAccessibility,
        label: String?
    ) async throws {
        if isLocked { throw SecureStoreError.locked }
        items[account] = Item(data: data, accessibility: accessibility, label: label, modifiedAt: Date())
    }

    func delete(account: String) async throws {
        if isLocked { throw SecureStoreError.locked }
        items.removeValue(forKey: account)
    }

    func attributes(account: String) async throws -> SecureStoreItemAttributes? {
        if isLocked { throw SecureStoreError.locked }
        guard let item = items[account] else { return nil }
        return SecureStoreItemAttributes(
            accessibility: item.accessibility,
            label: item.label,
            modifiedAt: item.modifiedAt
        )
    }

    // MARK: - Test support

    /// Plants a legacy-shaped item exactly as an older build would have written it.
    func seed(account: String, string: String, accessibility: SecureStoreAccessibility = .afterFirstUnlock) {
        items[account] = Item(
            data: Data(string.utf8),
            accessibility: accessibility,
            label: nil,
            modifiedAt: Date()
        )
    }

    func seed(account: String, data: Data, accessibility: SecureStoreAccessibility = .afterFirstUnlock) {
        items[account] = Item(data: data, accessibility: accessibility, label: nil, modifiedAt: Date())
    }

    func setLocked(_ locked: Bool) {
        isLocked = locked
    }

    var accounts: [String] {
        items.keys.sorted()
    }

    func rawData(account: String) -> Data? {
        items[account]?.data
    }
}
