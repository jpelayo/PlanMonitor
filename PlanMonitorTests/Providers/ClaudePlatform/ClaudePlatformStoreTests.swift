import Foundation
import Testing
@testable import PlanMonitor

@Suite("Claude-API stores")
struct ClaudePlatformStoreTests {
    private static let fixedDate = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - Snapshot

    @Test func snapshotRoundTrips() throws {
        try withDefaults { defaults in
            let store = ClaudePlatformSnapshotStore(defaults: defaults)
            let snapshot = try ClaudePlatformFixtures.capturedSnapshot()

            store.save(snapshot: snapshot, lastUpdated: Self.fixedDate)

            let loaded = try #require(store.load())
            #expect(loaded.snapshot == snapshot)
            #expect(loaded.lastUpdated == Self.fixedDate)
            #expect(loaded.providerID == .claudeapi)
        }
    }

    /// A blob tagged with another provider must never be read as this one's money — without the
    /// guard this is silent.
    @Test func aSnapshotTaggedForAnotherProviderIsRejected() throws {
        try withDefaults { defaults in
            let foreign = ClaudePlatformPersistedSnapshot(
                schemaVersion: ClaudePlatformSnapshotStore.schemaVersion,
                providerID: .openrouter,
                snapshot: try ClaudePlatformFixtures.capturedSnapshot(),
                lastUpdated: Self.fixedDate
            )
            defaults.set(try JSONEncoder().encode(foreign), forKey: ClaudePlatformSnapshotStore.key)

            #expect(ClaudePlatformSnapshotStore(defaults: defaults).load() == nil)
        }
    }

    @Test func anotherSchemaVersionIsRejected() throws {
        try withDefaults { defaults in
            let future = ClaudePlatformPersistedSnapshot(
                schemaVersion: ClaudePlatformSnapshotStore.schemaVersion + 1,
                providerID: .claudeapi,
                snapshot: try ClaudePlatformFixtures.capturedSnapshot(),
                lastUpdated: Self.fixedDate
            )
            defaults.set(try JSONEncoder().encode(future), forKey: ClaudePlatformSnapshotStore.key)

            #expect(ClaudePlatformSnapshotStore(defaults: defaults).load() == nil)
        }
    }

    @Test func savingAnEmptySnapshotClears() throws {
        try withDefaults { defaults in
            let store = ClaudePlatformSnapshotStore(defaults: defaults)
            store.save(snapshot: try ClaudePlatformFixtures.capturedSnapshot(), lastUpdated: Self.fixedDate)
            store.save(snapshot: .empty, lastUpdated: Self.fixedDate)

            #expect(defaults.data(forKey: ClaudePlatformSnapshotStore.key) == nil)
        }
    }

    // MARK: - Credential

    /// `sessionKey` is Claude's App Store-era account; writing it would sign Claude out.
    @Test func theAccountIsNamespacedAndNotClaudes() {
        #expect(ClaudePlatformCredentialStore.account == "claudeapi.session")
        #expect(ClaudePlatformCredentialStore.account != ClaudeCredentialStore.account)
    }

    @Test func sessionRoundTrips() async throws {
        let memory = InMemorySecureStore()
        let store = ClaudePlatformCredentialStore(secureStore: memory)
        let session = ClaudePlatformSession(
            cookieHeader: "sessionKey=abc; __cf_bm=edge",
            identityLabel: "someone@example.com",
            organizationID: ClaudePlatformFixtures.organizationID,
            organizationName: "Console",
            capturedAt: Self.fixedDate
        )

        try await store.save(session)

        #expect(try await store.load() == session)
        #expect(await memory.accounts == [ClaudePlatformCredentialStore.account])
    }

    @Test func rotatedCookiesKeepTheIdentity() async throws {
        let store = ClaudePlatformCredentialStore(secureStore: InMemorySecureStore())
        try await store.save(ClaudePlatformSession(
            cookieHeader: "sessionKey=old",
            identityLabel: "someone@example.com",
            organizationID: "org",
            organizationName: "Console",
            capturedAt: Self.fixedDate
        ))

        await store.updateCookieHeader("sessionKey=new")

        let loaded = try #require(try await store.load())
        #expect(loaded.cookieHeader == "sessionKey=new")
        #expect(loaded.identityLabel == "someone@example.com")
        #expect(loaded.organizationID == "org")
    }

    @Test func deleteRemovesOnlyItsOwnAccount() async throws {
        let memory = InMemorySecureStore()
        try await ClaudeCredentialStore(secureStore: memory)
            .save(ClaudeSession(cookieHeader: "sessionKey=claude", capturedAt: Self.fixedDate))
        let store = ClaudePlatformCredentialStore(secureStore: memory)
        try await store.save(ClaudePlatformSession(cookieHeader: "sessionKey=console", capturedAt: Self.fixedDate))

        try await store.delete()

        #expect(await memory.accounts == [ClaudeCredentialStore.account])
    }
}
