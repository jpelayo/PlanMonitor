import Foundation
import Testing
@testable import PlanMonitor

/// x.ai spends a refresh token on use (verified live, 2026-11-06), so the new one is the only live
/// copy from the moment a refresh succeeds. Losing it costs the user a full sign-in.
@Suite("Grok token rotation")
struct GrokTokenRotationTests {
    private struct Harness {
        let token: String
        let memory = InMemorySecureStore()
        let store: GrokCredentialStore
        let service: GrokAuthenticationService

        init(_ token: String, answers: [GrokOIDCStub.Answer]) {
            self.token = token
            store = GrokCredentialStore(secureStore: memory)
            service = GrokAuthenticationService(
                apiClient: GrokAPIClient(),
                oidcClient: GrokOIDCClient(session: GrokOIDCStub.session(token, answers: answers)),
                credentialStore: store
            )
        }

        var sentRefreshTokens: [String?] {
            GrokOIDCStub.forms(for: token).map { $0["refresh_token"] }
        }
    }

    /// The launch read the Keychain; it locked afterwards, so only the save meets the lock.
    private func launched(_ harness: Harness) async throws {
        try await harness.store.save(GrokOIDCFixtures.credentials(refresh: "refresh-0", expiresIn: 3600))
        #expect(await harness.service.restoreStoredSession() == .restored(email: "someone@example.com"))
        await harness.memory.setLocked(true)
    }

    @Test func aFailedSaveKeepsTheRotatedToken() async throws {
        let harness = Harness("grok-rotation-locked", answers: [
            .json(status: 200, GrokOIDCFixtures.tokenAnswer(access: "access-1", refresh: "refresh-1")),
            .json(status: 200, GrokOIDCFixtures.tokenAnswer(access: "access-2", refresh: "refresh-2"))
        ])
        try await launched(harness)

        try await harness.service.refreshAccessTokenIfNeeded(force: true)
        // The Keychain is locked, so this copy exists nowhere else. The next refresh must spend it,
        // not the old one.
        try await harness.service.refreshAccessTokenIfNeeded(force: true)

        #expect(harness.sentRefreshTokens == ["refresh-0", "refresh-1"])
    }

    @Test func theSaveIsRetriedOnceTheKeychainOpens() async throws {
        let harness = Harness("grok-rotation-retry", answers: [
            .json(status: 200, GrokOIDCFixtures.tokenAnswer(access: "access-1", refresh: "refresh-1"))
        ])
        try await launched(harness)

        try await harness.service.refreshAccessTokenIfNeeded(force: true)
        await harness.memory.setLocked(false)
        #expect(try await harness.store.load()?.refreshToken == "refresh-0")

        // The next cycle: the token is fresh, so nothing is sent, but the save is retried.
        try await harness.service.refreshAccessTokenIfNeeded()

        #expect(try await harness.store.load()?.refreshToken == "refresh-1")
        #expect(harness.sentRefreshTokens == ["refresh-0"])
    }

    @Test func aKeychainThatLocksLaterDoesNotStopThePoll() async throws {
        let harness = Harness("grok-rotation-locked-later", answers: [])
        try await launched(harness)

        try await harness.service.refreshAccessTokenIfNeeded()

        #expect(harness.sentRefreshTokens.isEmpty)
    }

    /// Two callers can read the same credentials before either refreshes. The second one holds a
    /// spent token, and sending it would earn `invalid_grant` and delete good credentials.
    @Test func aSpentTokenIsNeverSentTwice() async throws {
        let harness = Harness("grok-rotation-spent", answers: [
            .json(status: 200, GrokOIDCFixtures.tokenAnswer(access: "access-1", refresh: "refresh-1"))
        ])
        try await harness.store.save(GrokOIDCFixtures.credentials(refresh: "refresh-0"))

        async let first: Void = harness.service.refreshAccessTokenIfNeeded()
        async let second: Void = harness.service.refreshAccessTokenIfNeeded()
        _ = try await (first, second)

        #expect(harness.sentRefreshTokens == ["refresh-0"])
        #expect(try await harness.store.load()?.refreshToken == "refresh-1")
    }

    @Test func aFreshTokenIsNotRefreshed() async throws {
        let harness = Harness("grok-rotation-fresh", answers: [])
        try await harness.store.save(GrokOIDCFixtures.credentials(expiresIn: 3600))

        try await harness.service.refreshAccessTokenIfNeeded()

        #expect(harness.sentRefreshTokens.isEmpty)
    }

    @Test func invalidGrantStillDeletesTheCredentials() async throws {
        let harness = Harness("grok-rotation-invalid", answers: [
            .json(status: 400, #"{"error":"invalid_grant"}"#)
        ])
        try await harness.store.save(GrokOIDCFixtures.credentials())

        let error = await #expect(throws: GrokAPIError.self) {
            try await harness.service.refreshAccessTokenIfNeeded()
        }

        guard case .noAccessToken? = error else {
            Issue.record("expected noAccessToken, got \(String(describing: error))")
            return
        }
        #expect(try await harness.store.load() == nil)
    }

    @Test func aNetworkFailureDeletesNothing() async throws {
        let harness = Harness("grok-rotation-offline", answers: [.networkFailure])
        try await harness.store.save(GrokOIDCFixtures.credentials(refresh: "refresh-0"))

        await #expect(throws: (any Error).self) {
            try await harness.service.refreshAccessTokenIfNeeded()
        }

        #expect(try await harness.store.load()?.refreshToken == "refresh-0")
    }

    // MARK: - Restore

    @Test func restoreRefreshesAStaleTokenAndSavesIt() async throws {
        let harness = Harness("grok-restore-stale", answers: [
            .json(status: 200, GrokOIDCFixtures.tokenAnswer(access: "access-1", refresh: "refresh-1"))
        ])
        try await harness.store.save(GrokOIDCFixtures.credentials(refresh: "refresh-0"))

        #expect(await harness.service.restoreStoredSession() == .restored(email: "someone@example.com"))

        #expect(harness.sentRefreshTokens == ["refresh-0"])
        #expect(try await harness.store.load()?.refreshToken == "refresh-1")
    }

    /// Offline at launch: the token we have stays, and the poll retries.
    @Test func restoreKeepsTheTokenWhenOffline() async throws {
        let harness = Harness("grok-restore-offline", answers: [.networkFailure])
        try await harness.store.save(GrokOIDCFixtures.credentials(refresh: "refresh-0"))

        #expect(await harness.service.restoreStoredSession() == .restored(email: "someone@example.com"))

        #expect(try await harness.store.load()?.refreshToken == "refresh-0")
    }

    @Test func aTokenIsRestoredWithItsEmail() async throws {
        let harness = Harness("grok-restore-token", answers: [])
        try await harness.store.save(GrokOIDCFixtures.credentials(expiresIn: 3600))
        #expect(await harness.service.restoreStoredSession() == .restored(email: "someone@example.com"))
    }

    /// Cookies from the old flow are no sign-in any more: nothing can read usage with them.
    @Test func oldCookiesWithoutATokenAreAbsent() async throws {
        let harness = Harness("grok-restore-cookies", answers: [])
        try await harness.store.saveSession(GrokWebSession(cookieHeader: "sso=abc", email: "g@example.com"))
        #expect(await harness.service.restoreStoredSession() == .absent)
    }

    @Test func aLockedKeychainIsUnavailableNotAbsent() async throws {
        let harness = Harness("grok-restore-locked", answers: [])
        try await harness.store.save(GrokOIDCFixtures.credentials(expiresIn: 3600))
        await harness.memory.setLocked(true)
        #expect(await harness.service.restoreStoredSession() == .unavailable)
    }

    // MARK: - Approval

    @Test func anApprovalReplacesTheOldCookies() async throws {
        let harness = Harness("grok-approval", answers: [
            .json(status: 200, GrokOIDCFixtures.tokenAnswer()),
            .json(status: 200, GrokOIDCFixtures.userInfo)
        ])
        try await harness.store.saveSession(GrokWebSession(cookieHeader: "sso=abc", email: "g@example.com"))

        let credentials = try await harness.service.completeDeviceAuthorization(GrokOIDCFixtures.authorization())

        #expect(credentials.email == "someone@example.com")
        #expect(try await harness.store.load()?.accessToken == "access-1")
        #expect(try await harness.store.loadSession() == nil)
    }
}
