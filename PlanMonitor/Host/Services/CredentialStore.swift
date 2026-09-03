import Foundation

/// One Keychain account, one payload type. Reads try the current envelope first and, when
/// that fails to decode, every legacy shape an older build could have left behind — under
/// the same account or a legacy account name — upgrading the first match in place. Old
/// credentials are therefore never discarded by a format change; only explicit sign-out or a
/// definitive rejection by the provider removes them.
actor CredentialStore<Payload: VersionedCredentialPayload> {
    /// How to read one pre-envelope shape. Return `nil` when the bytes are not that shape.
    typealias LegacyDecoder = @Sendable (Data) -> Payload?

    struct LegacyAccount: Sendable {
        let account: String
        let decoders: [LegacyDecoder]

        init(_ account: String, decoders: [LegacyDecoder]) {
            self.account = account
            self.decoders = decoders
        }
    }

    enum LoadOutcome: Sendable {
        case absent
        case current(Payload)
        /// Found in an old shape and rewritten as an envelope.
        case upgraded(Payload)
        /// Bytes exist but no decoder recognised them. Left in place for inspection.
        case unreadable
    }

    private let store: any SecureStore
    private let provider: ProviderID
    private let kind: String
    private let account: String
    private let accessibility: SecureStoreAccessibility
    private let legacyDecoders: [LegacyDecoder]
    private let legacyAccounts: [LegacyAccount]
    private let onUnreadable: (@Sendable () -> Void)?

    init(
        store: any SecureStore,
        provider: ProviderID,
        kind: String,
        account: String,
        accessibility: SecureStoreAccessibility = .afterFirstUnlockThisDeviceOnly,
        legacyDecoders: [LegacyDecoder] = [],
        legacyAccounts: [LegacyAccount] = [],
        onUnreadable: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.provider = provider
        self.kind = kind
        self.account = account
        self.accessibility = accessibility
        self.legacyDecoders = legacyDecoders
        self.legacyAccounts = legacyAccounts
        self.onUnreadable = onUnreadable
    }

    var label: String {
        "PlanMonitor · \(provider.displayName) \(kind)"
    }

    /// The payload, or `nil` when nothing is stored. Keychain errors other than absence
    /// (`.locked`, `.missingEntitlement`, …) propagate; callers must treat them as transient.
    func load() async throws -> Payload? {
        switch try await loadDetailed() {
        case .current(let payload), .upgraded(let payload):
            return payload
        case .absent, .unreadable:
            return nil
        }
    }

    func loadDetailed() async throws -> LoadOutcome {
        let decoder = CredentialCodec.decoder()

        if let data = try await store.read(account: account) {
            if let envelope = try? decoder.decode(CredentialEnvelope<Payload>.self, from: data),
               envelope.format == CredentialEnvelope<Payload>.currentFormat {
                return .current(envelope.payload)
            }
            if let payload = decodeLegacy(data, with: legacyDecoders) {
                try await save(payload)
                return .upgraded(payload)
            }
            if let payload = try await upgradeFromLegacyAccounts() {
                return .upgraded(payload)
            }
            onUnreadable?()
            return .unreadable
        }

        if let payload = try await upgradeFromLegacyAccounts() {
            return .upgraded(payload)
        }
        return .absent
    }

    func save(_ payload: Payload) async throws {
        let existing = try? await loadEnvelope()
        let envelope = CredentialEnvelope(
            provider: provider,
            kind: kind,
            payload: payload,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )
        let data = try CredentialCodec.encoder().encode(envelope)
        try await store.write(account: account, data: data, accessibility: accessibility, label: label)
    }

    /// Removes the current item and every legacy account this store knows about.
    func delete() async throws {
        try await store.delete(account: account)
        for legacy in legacyAccounts {
            try? await store.delete(account: legacy.account)
        }
    }

    func hasCredential() async -> Bool {
        (try? await load()) != nil
    }

    // MARK: - Private

    private func loadEnvelope() async throws -> CredentialEnvelope<Payload>? {
        guard let data = try await store.read(account: account) else { return nil }
        return try? CredentialCodec.decoder().decode(CredentialEnvelope<Payload>.self, from: data)
    }

    private func upgradeFromLegacyAccounts() async throws -> Payload? {
        for legacy in legacyAccounts {
            guard let data = try await store.read(account: legacy.account) else { continue }
            guard let payload = decodeLegacy(data, with: legacy.decoders) else { continue }
            try await save(payload)
            try? await store.delete(account: legacy.account)
            return payload
        }
        return nil
    }

    private func decodeLegacy(_ data: Data, with decoders: [LegacyDecoder]) -> Payload? {
        for decoder in decoders {
            if let payload = decoder(data) {
                return payload
            }
        }
        return nil
    }
}

extension CredentialStore {
    /// Decoder for a legacy item that was a bare UTF-8 string.
    static func rawString(_ transform: @escaping @Sendable (String) -> Payload?) -> LegacyDecoder {
        { data in
            guard let string = String(data: data, encoding: .utf8) else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            // A JSON object is never a valid raw credential in any provider.
            guard !trimmed.hasPrefix("{") else { return nil }
            return transform(trimmed)
        }
    }

    /// Decoder for a legacy item that was a bare JSON payload with the given date strategy.
    static func bareJSON<Legacy: Decodable>(
        _ type: Legacy.Type,
        dates: JSONDecoder.DateDecodingStrategy = .iso8601,
        _ transform: @escaping @Sendable (Legacy) -> Payload?
    ) -> LegacyDecoder {
        { data in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = dates
            guard let legacy = try? decoder.decode(Legacy.self, from: data) else { return nil }
            return transform(legacy)
        }
    }
}
