import Foundation
import Security

/// Generic-password items under one explicit service. The query shape is deliberately the
/// same one every previous PlanTracker build used — class, service, account — so items written
/// by the App Store Claude build are found. Two things are intentionally absent:
/// `kSecUseDataProtectionKeychain` and `kSecAttrAccessGroup`. Either would move lookups to a
/// different keychain and hide every existing item.
actor KeychainSecureStore: SecureStore {
    static let serviceIdentifier = "com.infinitecontext.plantracker"

    private let service: String

    init(service: String = KeychainSecureStore.serviceIdentifier) {
        self.service = service
    }

    func read(account: String) async throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SecureStoreError.decodeFailed(account: account)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw Self.error(for: status)
        }
    }

    func write(
        account: String,
        data: Data,
        accessibility: SecureStoreAccessibility,
        label: String?
    ) async throws {
        let existing = try await attributes(account: account)

        if let existing {
            // The accessibility class cannot be changed in place. When the stored class is
            // known and differs from the requested one, replace the item instead.
            if let storedClass = existing.accessibility, storedClass != accessibility {
                try await delete(account: account)
                try add(account: account, data: data, accessibility: accessibility, label: label)
                return
            }
            var attributes: [String: Any] = [kSecValueData as String: data]
            if let label {
                attributes[kSecAttrLabel as String] = label
            }
            let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
            switch status {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                // Raced with a delete; fall through to add.
                break
            default:
                throw Self.error(for: status)
            }
        }

        try add(account: account, data: data, accessibility: accessibility, label: label)
    }

    func delete(account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw Self.error(for: status)
        }
    }

    func attributes(account: String) async throws -> SecureStoreItemAttributes? {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            let dictionary = result as? [String: Any] ?? [:]
            return SecureStoreItemAttributes(
                accessibility: Self.accessibility(from: dictionary[kSecAttrAccessible as String]),
                label: dictionary[kSecAttrLabel as String] as? String,
                modifiedAt: dictionary[kSecAttrModificationDate as String] as? Date
            )
        case errSecItemNotFound:
            return nil
        default:
            throw Self.error(for: status)
        }
    }

    // MARK: - Private

    private func add(
        account: String,
        data: Data,
        accessibility: SecureStoreAccessibility,
        label: String?
    ) throws {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = Self.attributeValue(for: accessibility)
        if let label {
            query[kSecAttrLabel as String] = label
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Lost a race with a concurrent add. Update in place.
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else { throw Self.error(for: updateStatus) }
        default:
            throw Self.error(for: status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    private static func error(for status: OSStatus) -> SecureStoreError {
        switch status {
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled, errSecNotAvailable:
            return .locked
        case errSecMissingEntitlement:
            return .missingEntitlement
        default:
            return .unexpected(status)
        }
    }

    private static func attributeValue(for accessibility: SecureStoreAccessibility) -> CFString {
        switch accessibility {
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }

    private static func accessibility(from value: Any?) -> SecureStoreAccessibility? {
        guard let raw = value as? String else { return nil }
        switch raw as CFString {
        case kSecAttrAccessibleAfterFirstUnlock:
            return .afterFirstUnlock
        case kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly:
            return .afterFirstUnlockThisDeviceOnly
        default:
            return nil
        }
    }
}
