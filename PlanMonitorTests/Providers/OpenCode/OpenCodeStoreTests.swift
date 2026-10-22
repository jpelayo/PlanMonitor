import Foundation
import Testing
@testable import PlanMonitor

@Suite("OpenCode stores")
struct OpenCodeStoreTests {
    private static let fixedDate = Date(timeIntervalSince1970: 1_792_000_000)

    private static func snapshot() throws -> OpenCodeSnapshot {
        OpenCodeSnapshot.assemble(
            members: try OpenCodeFixtures.members(OpenCodeFixtures.docsExample),
            selectedMemberID: nil,
            fetchedAt: fixedDate
        )
    }

    // MARK: - Snapshot

    @Test func snapshotRoundTrips() throws {
        try withDefaults { defaults in
            let store = OpenCodeSnapshotStore(defaults: defaults)
            let snapshot = try Self.snapshot()

            store.save(snapshot: snapshot, lastUpdated: Self.fixedDate)

            let loaded = try #require(store.load())
            #expect(loaded.snapshot == snapshot)
            #expect(loaded.lastUpdated == Self.fixedDate)
            #expect(loaded.providerID == .opencode)
        }
    }

    /// A blob tagged with another provider must never be read as this one's money — without the
    /// guard this is silent.
    @Test func aSnapshotTaggedForAnotherProviderIsRejected() throws {
        try withDefaults { defaults in
            let foreign = OpenCodePersistedSnapshot(
                schemaVersion: OpenCodeSnapshotStore.schemaVersion,
                providerID: .openrouter,
                snapshot: try Self.snapshot(),
                lastUpdated: Self.fixedDate
            )
            defaults.set(try JSONEncoder().encode(foreign), forKey: OpenCodeSnapshotStore.key)

            #expect(OpenCodeSnapshotStore(defaults: defaults).load() == nil)
        }
    }

    @Test func anotherSchemaVersionIsRejected() throws {
        try withDefaults { defaults in
            let future = OpenCodePersistedSnapshot(
                schemaVersion: OpenCodeSnapshotStore.schemaVersion + 1,
                providerID: .opencode,
                snapshot: try Self.snapshot(),
                lastUpdated: Self.fixedDate
            )
            defaults.set(try JSONEncoder().encode(future), forKey: OpenCodeSnapshotStore.key)

            #expect(OpenCodeSnapshotStore(defaults: defaults).load() == nil)
        }
    }

    @Test func savingAnEmptySnapshotClears() throws {
        try withDefaults { defaults in
            let store = OpenCodeSnapshotStore(defaults: defaults)
            store.save(snapshot: try Self.snapshot(), lastUpdated: Self.fixedDate)
            store.save(snapshot: .empty, lastUpdated: Self.fixedDate)

            #expect(defaults.data(forKey: OpenCodeSnapshotStore.key) == nil)
        }
    }

    // MARK: - Credential

    @Test func theAccountIsNamespaced() {
        #expect(OpenCodeCredentialStore.account == "opencode.apiKey")
        #expect(OpenCodeCredentialStore.account != OpenRouterCredentialStore.account)
    }

    @Test func theKeyRoundTrips() async throws {
        let memory = InMemorySecureStore()
        let store = OpenCodeCredentialStore(secureStore: memory)
        let key = OpenCodeAPIKey(key: OpenCodeFixtures.testKey, validatedAt: Self.fixedDate)

        try await store.save(key)

        #expect(try await OpenCodeCredentialStore(secureStore: memory).load() == key)
        #expect(await memory.accounts == [OpenCodeCredentialStore.account])
    }

    @Test func clearRemovesOnlyItsOwnAccount() async throws {
        let memory = InMemorySecureStore()
        try await OpenRouterCredentialStore(secureStore: memory)
            .save(OpenRouterManagementKey(key: "sk-or-v1-openrouter", validatedAt: Self.fixedDate))
        let store = OpenCodeCredentialStore(secureStore: memory)
        try await store.save(OpenCodeAPIKey(key: OpenCodeFixtures.testKey, validatedAt: Self.fixedDate))

        await store.clear()

        #expect(await memory.accounts == [OpenRouterCredentialStore.account])
        #expect(try await store.load() == nil)
    }
}
