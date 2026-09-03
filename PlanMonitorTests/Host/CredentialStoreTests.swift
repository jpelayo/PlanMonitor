import Foundation
import Testing
@testable import PlanTracker

/// Exercises the provider credential stores against `InMemorySecureStore`: envelope
/// shape on disk, every legacy shape an older build could have left behind, locked-keychain
/// behaviour, unreadable bytes, sign-out isolation and the accessibility class of new writes.
@MainActor
struct CredentialStoreTests {
    /// Whole seconds so ISO-8601 (which drops fractions) round-trips exactly.
    private static let fixedDate = Date(timeIntervalSince1970: 1_756_720_000)
    private static let isoPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/

    // MARK: - Envelope round-trips

    @Test func claudeSessionRoundTripsThroughEnvelope() async throws {
        let memory = InMemorySecureStore()
        let store = ClaudeCredentialStore(secureStore: memory)
        let session = ClaudeSession(cookieHeader: "sessionKey=sk-ant-abc; other=1", email: "a@example.com", capturedAt: Self.fixedDate)

        try await store.save(session)

        let raw = await memory.rawData(account: ClaudeCredentialStore.account)
        let payload = try Self.assertEnvelope(raw, provider: .claude, kind: "session", as: ClaudeSession.self)
        #expect(payload == session)
        let loaded = try await store.load()
        #expect(loaded == session)
    }

    @Test func codexSessionRoundTripsThroughEnvelope() async throws {
        let memory = InMemorySecureStore()
        let store = CodexCredentialStore(secureStore: memory)
        let session = CodexSession(cookieHeader: "__Secure-next-auth.session-token=xyz", identityLabel: "c@example.com", capturedAt: Self.fixedDate)

        try await store.save(session)

        let raw = await memory.rawData(account: CodexCredentialStore.account)
        let payload = try Self.assertEnvelope(raw, provider: .codex, kind: "session", as: CodexSession.self)
        #expect(payload == session)
        let loaded = try await store.load()
        #expect(loaded == session)
    }

    @Test func grokWebSessionRoundTripsThroughEnvelope() async throws {
        let memory = InMemorySecureStore()
        let store = GrokCredentialStore(secureStore: memory)
        let session = GrokWebSession(cookieHeader: "sso=abc; sso-rw=def", email: "g@example.com", savedAt: Self.fixedDate)

        try await store.saveSession(session)

        let raw = await memory.rawData(account: GrokCredentialStore.sessionAccount)
        let payload = try Self.assertEnvelope(raw, provider: .grok, kind: "session", as: GrokWebSession.self)
        #expect(payload == session)
        let loaded = try await store.loadSession()
        #expect(loaded == session)
    }

    @Test func grokCredentialsRoundTripThroughEnvelope() async throws {
        let memory = InMemorySecureStore()
        let store = GrokCredentialStore(secureStore: memory)
        let credentials = Self.grokCredentials()

        try await store.save(credentials)

        let raw = await memory.rawData(account: GrokCredentialStore.credentialsAccount)
        let payload = try Self.assertEnvelope(raw, provider: .grok, kind: "oidc", as: GrokCredentials.self)
        #expect(payload == credentials)
        let loaded = try await store.load()
        #expect(loaded == credentials)
    }

    @Test func openRouterManagementKeyRoundTripsThroughEnvelope() async throws {
        let memory = InMemorySecureStore()
        let store = OpenRouterCredentialStore(secureStore: memory)
        let key = OpenRouterManagementKey(key: "sk-or-v1-abc", keyLabel: "sk-or-v1-a…c", validatedAt: Self.fixedDate)

        try await store.save(key)

        let raw = await memory.rawData(account: OpenRouterCredentialStore.account)
        let payload = try Self.assertEnvelope(raw, provider: .openrouter, kind: "managementKey", as: OpenRouterManagementKey.self)
        #expect(payload == key)
        // A fresh store instance so the in-memory cache is not what answers.
        let loaded = try await OpenRouterCredentialStore(secureStore: memory).load()
        #expect(loaded == key)
    }

    // MARK: - Legacy upgrades

    @Test func rawBareClaudeCookieValueUpgradesToFullHeader() async throws {
        let memory = InMemorySecureStore()
        await memory.seed(account: ClaudeCredentialStore.account, string: "sk-ant-sid01-abc")
        let store = ClaudeCredentialStore(secureStore: memory)

        let loaded = try await store.load()

        #expect(loaded?.cookieHeader == "sessionKey=sk-ant-sid01-abc")
        #expect(loaded?.email == nil)
        let current = try await Self.strictCurrent(ClaudeSession.self, account: ClaudeCredentialStore.account, provider: .claude, kind: "session", in: memory)
        #expect(current == loaded)
    }

    @Test func rawFullClaudeHeaderUpgradesUnchanged() async throws {
        let memory = InMemorySecureStore()
        await memory.seed(account: ClaudeCredentialStore.account, string: "sessionKey=sk-ant-sid01-abc; lastActiveOrg=org_1")
        let store = ClaudeCredentialStore(secureStore: memory)

        let loaded = try await store.load()

        #expect(loaded?.cookieHeader == "sessionKey=sk-ant-sid01-abc; lastActiveOrg=org_1")
        let current = try await Self.strictCurrent(ClaudeSession.self, account: ClaudeCredentialStore.account, provider: .claude, kind: "session", in: memory)
        #expect(current == loaded)
    }

    @Test func rawCodexCookieHeaderUpgrades() async throws {
        let memory = InMemorySecureStore()
        await memory.seed(account: CodexCredentialStore.account, string: "__Secure-next-auth.session-token=xyz; cf_clearance=1\n")
        let store = CodexCredentialStore(secureStore: memory)

        let loaded = try await store.load()

        #expect(loaded?.cookieHeader == "__Secure-next-auth.session-token=xyz; cf_clearance=1")
        let current = try await Self.strictCurrent(CodexSession.self, account: CodexCredentialStore.account, provider: .codex, kind: "session", in: memory)
        #expect(current == loaded)
    }

    @Test func bareJSONGrokSessionWithDefaultDatesUpgrades() async throws {
        struct LegacySeed: Encodable {
            var cookies: String
            var email: String?
            var savedAt: Date
        }
        let memory = InMemorySecureStore()
        // The previous build used a plain `JSONEncoder()`: seconds since the reference date.
        let seed = try JSONEncoder().encode(LegacySeed(cookies: "sso=abc; sso-rw=def", email: "g@example.com", savedAt: Self.fixedDate))
        await memory.seed(account: GrokCredentialStore.sessionAccount, data: seed)
        let store = GrokCredentialStore(secureStore: memory)

        let loaded = try await store.loadSession()

        #expect(loaded?.cookieHeader == "sso=abc; sso-rw=def")
        #expect(loaded?.email == "g@example.com")
        #expect(loaded?.savedAt == Self.fixedDate)
        let current = try await Self.strictCurrent(GrokWebSession.self, account: GrokCredentialStore.sessionAccount, provider: .grok, kind: "session", in: memory)
        #expect(current == loaded)
    }

    @Test func rawLegacyGrokSessionCookiesAccountMovesToCurrentAccount() async throws {
        let memory = InMemorySecureStore()
        await memory.seed(account: GrokCredentialStore.legacySessionAccount, string: "sso=legacy; sso-rw=legacy2")
        let store = GrokCredentialStore(secureStore: memory)

        let loaded = try await store.loadSession()

        #expect(loaded?.cookieHeader == "sso=legacy; sso-rw=legacy2")
        let accounts = await memory.accounts
        #expect(accounts == [GrokCredentialStore.sessionAccount])
        let current = try await Self.strictCurrent(GrokWebSession.self, account: GrokCredentialStore.sessionAccount, provider: .grok, kind: "session", in: memory)
        #expect(current == loaded)
    }

    @Test func bareJSONGrokCredentialsWithISODatesUpgrade() async throws {
        let memory = InMemorySecureStore()
        let credentials = Self.grokCredentials()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        await memory.seed(account: GrokCredentialStore.credentialsAccount, data: try encoder.encode(credentials))
        let store = GrokCredentialStore(secureStore: memory)

        let loaded = try await store.load()

        #expect(loaded == credentials)
        let current = try await Self.strictCurrent(GrokCredentials.self, account: GrokCredentialStore.credentialsAccount, provider: .grok, kind: "oidc", in: memory)
        #expect(current == credentials)
    }

    @Test func bareJSONLegacyGrokCredentialsAccountMovesToCurrentAccount() async throws {
        let memory = InMemorySecureStore()
        let credentials = Self.grokCredentials()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        await memory.seed(account: GrokCredentialStore.legacyCredentialsAccount, data: try encoder.encode(credentials))
        let store = GrokCredentialStore(secureStore: memory)

        let loaded = try await store.load()

        #expect(loaded == credentials)
        let accounts = await memory.accounts
        #expect(accounts == [GrokCredentialStore.credentialsAccount])
        let current = try await Self.strictCurrent(GrokCredentials.self, account: GrokCredentialStore.credentialsAccount, provider: .grok, kind: "oidc", in: memory)
        #expect(current == credentials)
    }

    @Test func rawOpenRouterManagementKeyUpgrades() async throws {
        let memory = InMemorySecureStore()
        await memory.seed(account: OpenRouterCredentialStore.account, string: "  sk-or-v1-legacy  ")
        let store = OpenRouterCredentialStore(secureStore: memory)

        let loaded = try await store.load()

        #expect(loaded?.key == "sk-or-v1-legacy")
        #expect(loaded?.keyLabel == nil)
        let current = try await Self.strictCurrent(OpenRouterManagementKey.self, account: OpenRouterCredentialStore.account, provider: .openrouter, kind: "managementKey", in: memory)
        #expect(current == loaded)
    }

    @Test func legacyUpgradeRewritesWithDeviceOnlyAccessibility() async throws {
        let memory = InMemorySecureStore()
        await memory.seed(account: ClaudeCredentialStore.account, string: "sk-ant-sid01-abc", accessibility: .afterFirstUnlock)

        _ = try await ClaudeCredentialStore(secureStore: memory).load()

        let attributes = try await memory.attributes(account: ClaudeCredentialStore.account)
        #expect(attributes?.accessibility == .afterFirstUnlockThisDeviceOnly)
    }

    // MARK: - Locked keychain

    @Test func lockedStoreThrowsLockedAndKeepsTheItem() async throws {
        let memory = InMemorySecureStore()
        await memory.seed(account: ClaudeCredentialStore.account, string: "sessionKey=abc")
        let store = ClaudeCredentialStore(secureStore: memory)
        await memory.setLocked(true)

        await #expect(throws: SecureStoreError.locked) {
            _ = try await store.load()
        }

        await memory.setLocked(false)
        let raw = await memory.rawData(account: ClaudeCredentialStore.account)
        #expect(raw == Data("sessionKey=abc".utf8))
        let accounts = await memory.accounts
        #expect(accounts == [ClaudeCredentialStore.account])
    }

    @Test func claudeRestoreReportsUnavailableWhileLocked() async throws {
        await withDefaultsAsync { defaults in
            let memory = InMemorySecureStore()
            await memory.seed(account: ClaudeCredentialStore.account, string: "sessionKey=abc")
            let service = ClaudeAuthenticationService(
                credentialStore: ClaudeCredentialStore(secureStore: memory),
                apiClient: ClaudeAPIClient(),
                defaults: defaults
            )

            await memory.setLocked(true)
            let locked = await service.restoreStoredSession()
            #expect(locked == .unavailable)

            await memory.setLocked(false)
            let unlocked = await service.restoreStoredSession()
            #expect(unlocked == .restored(identity: nil))
        }
    }

    @Test func codexRestoreReportsUnavailableWhileLocked() async throws {
        await withDefaultsAsync { defaults in
            let memory = InMemorySecureStore()
            await memory.seed(account: CodexCredentialStore.account, string: "__Secure-next-auth.session-token=xyz")
            let service = CodexAuthenticationService(
                credentialStore: CodexCredentialStore(secureStore: memory),
                apiClient: OpenAIAPIClient(),
                defaults: defaults
            )

            await memory.setLocked(true)
            let locked = await service.restoreStoredSession()
            #expect(locked == .unavailable)

            await memory.setLocked(false)
            let unlocked = await service.restoreStoredSession()
            #expect(unlocked == .restored(identity: nil))
        }
    }

    @Test func absentCredentialRestoresAsAbsent() async throws {
        await withDefaultsAsync { defaults in
            let memory = InMemorySecureStore()
            let service = ClaudeAuthenticationService(
                credentialStore: ClaudeCredentialStore(secureStore: memory),
                apiClient: ClaudeAPIClient(),
                defaults: defaults
            )
            let result = await service.restoreStoredSession()
            #expect(result == .absent)
        }
    }

    // MARK: - Unreadable bytes

    @Test func unreadableBytesAreReportedAndLeftInPlace() async throws {
        let memory = InMemorySecureStore()
        // 0xFF never appears in valid UTF-8, so no raw-string decoder can claim these bytes.
        let garbage = Data([0xFF, 0xFE, 0xFA, 0x00, 0x01, 0xC3, 0x28])
        await memory.seed(account: ClaudeCredentialStore.account, data: garbage)
        let generic = CredentialStore<ClaudeSession>(
            store: memory,
            provider: .claude,
            kind: "session",
            account: ClaudeCredentialStore.account,
            legacyDecoders: [CredentialStore<ClaudeSession>.rawString { ClaudeSession(cookieHeader: $0) }]
        )

        let outcome = try await generic.loadDetailed()
        guard case .unreadable = outcome else {
            Issue.record("expected .unreadable, got \(outcome)")
            return
        }

        let loadedViaProvider = try await ClaudeCredentialStore(secureStore: memory).load()
        #expect(loadedViaProvider == nil)
        let raw = await memory.rawData(account: ClaudeCredentialStore.account)
        #expect(raw == garbage)
    }

    @Test func unknownJSONObjectIsUnreadableNotACookie() async throws {
        let memory = InMemorySecureStore()
        let bytes = Data(#"{"something":"else"}"#.utf8)
        await memory.seed(account: ClaudeCredentialStore.account, data: bytes)

        let loaded = try await ClaudeCredentialStore(secureStore: memory).load()

        #expect(loaded == nil)
        let raw = await memory.rawData(account: ClaudeCredentialStore.account)
        #expect(raw == bytes)
    }

    // MARK: - Sign-out isolation

    @Test func claudeSignOutLeavesOtherProvidersUntouched() async throws {
        let memory = try await Self.seedAllProviders()
        let before = await Self.rawSnapshot(memory)

        try await ClaudeCredentialStore(secureStore: memory).delete()

        let accounts = await memory.accounts
        #expect(!accounts.contains(ClaudeCredentialStore.account))
        let after = await Self.rawSnapshot(memory)
        for account in Self.allAccounts where account != ClaudeCredentialStore.account {
            #expect(after[account] == before[account], "\(account) changed")
        }
    }

    @Test func codexSignOutLeavesOtherProvidersUntouched() async throws {
        let memory = try await Self.seedAllProviders()
        let before = await Self.rawSnapshot(memory)

        try await CodexCredentialStore(secureStore: memory).delete()

        let accounts = await memory.accounts
        #expect(!accounts.contains(CodexCredentialStore.account))
        let after = await Self.rawSnapshot(memory)
        for account in Self.allAccounts where account != CodexCredentialStore.account {
            #expect(after[account] == before[account], "\(account) changed")
        }
    }

    @Test func grokSignOutRemovesBothGrokAccountsAndLegacyNamesOnly() async throws {
        let memory = try await Self.seedAllProviders()
        await memory.seed(account: GrokCredentialStore.legacySessionAccount, string: "sso=old")
        await memory.seed(account: GrokCredentialStore.legacyCredentialsAccount, string: "{}")
        let before = await Self.rawSnapshot(memory)

        try await GrokCredentialStore(secureStore: memory).deleteAll()

        let accounts = await memory.accounts
        let grokAccounts = [
            GrokCredentialStore.sessionAccount,
            GrokCredentialStore.credentialsAccount,
            GrokCredentialStore.legacySessionAccount,
            GrokCredentialStore.legacyCredentialsAccount
        ]
        for account in grokAccounts {
            #expect(!accounts.contains(account), "\(account) survived sign-out")
        }
        let after = await Self.rawSnapshot(memory)
        for account in Self.allAccounts where !grokAccounts.contains(account) {
            #expect(after[account] == before[account], "\(account) changed")
        }
    }

    @Test func openRouterDisconnectLeavesOtherProvidersUntouched() async throws {
        let memory = try await Self.seedAllProviders()
        let before = await Self.rawSnapshot(memory)

        await OpenRouterCredentialStore(secureStore: memory).clear()

        let accounts = await memory.accounts
        #expect(!accounts.contains(OpenRouterCredentialStore.account))
        let after = await Self.rawSnapshot(memory)
        for account in Self.allAccounts where account != OpenRouterCredentialStore.account {
            #expect(after[account] == before[account], "\(account) changed")
        }
    }

    // MARK: - Accessibility

    @Test func newWritesUseDeviceOnlyAccessibilityAndALabel() async throws {
        let memory = try await Self.seedAllProviders()
        let expectedLabels: [String: String] = [
            ClaudeCredentialStore.account: "PlanTracker · Claude session",
            CodexCredentialStore.account: "PlanTracker · Codex session",
            GrokCredentialStore.sessionAccount: "PlanTracker · Grok session",
            GrokCredentialStore.credentialsAccount: "PlanTracker · Grok oidc",
            OpenRouterCredentialStore.account: "PlanTracker · OpenRouter managementKey"
        ]

        for account in Self.allAccounts {
            let attributes = try await memory.attributes(account: account)
            #expect(attributes?.accessibility == .afterFirstUnlockThisDeviceOnly, Comment(rawValue: account))
            #expect(attributes?.label == expectedLabels[account], Comment(rawValue: account))
        }
    }

    // MARK: - Helpers

    private static let allAccounts = [
        ClaudeCredentialStore.account,
        CodexCredentialStore.account,
        GrokCredentialStore.sessionAccount,
        GrokCredentialStore.credentialsAccount,
        OpenRouterCredentialStore.account
    ]

    private static func seedAllProviders() async throws -> InMemorySecureStore {
        let memory = InMemorySecureStore()
        try await ClaudeCredentialStore(secureStore: memory)
            .save(ClaudeSession(cookieHeader: "sessionKey=claude", capturedAt: fixedDate))
        try await CodexCredentialStore(secureStore: memory)
            .save(CodexSession(cookieHeader: "token=codex", capturedAt: fixedDate))
        let grok = GrokCredentialStore(secureStore: memory)
        try await grok.saveSession(GrokWebSession(cookieHeader: "sso=grok", savedAt: fixedDate))
        try await grok.save(grokCredentials())
        try await OpenRouterCredentialStore(secureStore: memory)
            .save(OpenRouterManagementKey(key: "sk-or-v1-openrouter", validatedAt: fixedDate))
        let accounts = await memory.accounts
        #expect(accounts == allAccounts.sorted())
        return memory
    }

    private static func rawSnapshot(_ memory: InMemorySecureStore) async -> [String: Data] {
        var snapshot: [String: Data] = [:]
        for account in await memory.accounts {
            snapshot[account] = await memory.rawData(account: account)
        }
        return snapshot
    }

    private static func grokCredentials() -> GrokCredentials {
        GrokCredentials(
            schemaVersion: GrokCredentials.currentSchemaVersion,
            issuer: GrokCredentials.expectedIssuer,
            clientID: GrokCredentials.expectedClientID,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: fixedDate.addingTimeInterval(3600),
            tokenType: "Bearer",
            scopes: ["openid", "offline_access"],
            userID: "user-1",
            principalID: nil,
            principalType: "User",
            teamID: nil,
            email: "g@example.com",
            displayName: "Grok User",
            importedAt: fixedDate,
            refreshedAt: nil
        )
    }

    /// Reads the account with a store that knows no legacy shapes: `.current` proves the
    /// bytes are already an envelope and a second load needs no upgrade.
    private static func strictCurrent<Payload: VersionedCredentialPayload>(
        _ type: Payload.Type,
        account: String,
        provider: ProviderID,
        kind: String,
        in memory: InMemorySecureStore,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Payload? {
        let strict = CredentialStore<Payload>(store: memory, provider: provider, kind: kind, account: account)
        let outcome = try await strict.loadDetailed()
        guard case .current(let payload) = outcome else {
            Issue.record("expected .current, got \(outcome)", sourceLocation: sourceLocation)
            return nil
        }
        return payload
    }

    /// Decodes the raw bytes as an envelope and checks the on-disk contract: format 1,
    /// provider, kind, sorted keys and ISO-8601 dates.
    @discardableResult
    private static func assertEnvelope<Payload: VersionedCredentialPayload>(
        _ raw: Data?,
        provider: ProviderID,
        kind: String,
        as type: Payload.Type,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Payload {
        let data = try #require(raw, "nothing stored", sourceLocation: sourceLocation)
        let envelope = try CredentialCodec.decoder().decode(CredentialEnvelope<Payload>.self, from: data)
        #expect(envelope.format == 1, sourceLocation: sourceLocation)
        #expect(envelope.provider == provider, sourceLocation: sourceLocation)
        #expect(envelope.kind == kind, sourceLocation: sourceLocation)
        #expect(envelope.payload.schemaVersion == Payload.currentSchemaVersion, sourceLocation: sourceLocation)

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
        #expect(Set(object.keys) == ["createdAt", "format", "kind", "payload", "provider", "updatedAt"], sourceLocation: sourceLocation)
        #expect(object["format"] as? Int == 1, sourceLocation: sourceLocation)
        #expect(object["provider"] as? String == provider.rawValue, sourceLocation: sourceLocation)
        #expect(object["kind"] as? String == kind, sourceLocation: sourceLocation)
        for dateKey in ["createdAt", "updatedAt"] {
            let value = try #require(object[dateKey] as? String, "\(dateKey) missing", sourceLocation: sourceLocation)
            #expect(value.wholeMatch(of: isoPattern) != nil, "\(dateKey) is not ISO-8601: \(value)", sourceLocation: sourceLocation)
        }

        let text = try #require(String(data: data, encoding: .utf8), sourceLocation: sourceLocation)
        let topLevelOrder = ["\"createdAt\"", "\"format\"", "\"kind\"", "\"payload\"", "\"provider\"", "\"updatedAt\""]
            .compactMap { text.range(of: $0)?.lowerBound }
        #expect(topLevelOrder.count == 6, sourceLocation: sourceLocation)
        #expect(topLevelOrder == topLevelOrder.sorted(), "top-level keys are not sorted: \(text)", sourceLocation: sourceLocation)

        let payloadObject = try #require(object["payload"] as? [String: Any], sourceLocation: sourceLocation)
        let payloadKeyOrder = payloadObject.keys.sorted().compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        #expect(payloadKeyOrder == payloadKeyOrder.sorted(), "payload keys are not sorted: \(text)", sourceLocation: sourceLocation)

        return envelope.payload
    }
}
