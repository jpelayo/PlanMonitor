import Foundation
import Testing
@testable import PlanMonitor

/// The approval poll and the refresh: what keeps waiting, what ends it, and what reaches the server.
@Suite("Grok OIDC client")
struct GrokOIDCClientTests {
    private func client(_ token: String, _ answers: [GrokOIDCStub.Answer]) -> GrokOIDCClient {
        GrokOIDCClient(session: GrokOIDCStub.session(token, answers: answers))
    }

    /// Records the waits instead of waiting.
    private actor Sleeps {
        private(set) var intervals: [TimeInterval] = []
        func add(_ interval: TimeInterval) { intervals.append(interval) }
    }

    // MARK: - Form encoding

    /// `.urlQueryAllowed` left these raw: a `+` reached the server as a space, an `&` split the
    /// field, and the refresh failed as `invalid_grant`, which deletes the credentials.
    @Test func aRefreshTokenReachesTheServerIntact() async throws {
        let token = "grok-oidc-encoding"
        let awkward = "a+b&c=d/e"
        let oidc = client(token, [.json(status: 200, GrokOIDCFixtures.tokenAnswer())])

        _ = try await oidc.refresh(credentials: GrokOIDCFixtures.credentials(refresh: awkward))

        let form = try #require(GrokOIDCStub.forms(for: token).first)
        #expect(form["refresh_token"] == awkward)
        #expect(form["grant_type"] == "refresh_token")
        #expect(form["client_id"] == GrokCredentials.expectedClientID)
    }

    // MARK: - Token answers

    @Test func theLiveTokenAnswerDecodes() async throws {
        let token = "grok-oidc-live-answer"
        let oidc = client(token, [.json(status: 200, GrokOIDCFixtures.tokenAnswer(access: "new", refresh: "rotated"))])
        let now = Date()

        let refreshed = try await oidc.refresh(credentials: GrokOIDCFixtures.credentials(), now: now)

        #expect(refreshed.accessToken == "new")
        #expect(refreshed.refreshToken == "rotated")
        #expect(refreshed.accessTokenExpiresAt == now.addingTimeInterval(21600))
    }

    // MARK: - The poll

    @Test func pendingThenSlowDownThenApproved() async throws {
        let token = "grok-oidc-poll"
        let oidc = client(token, [
            .json(status: 400, #"{"error":"authorization_pending"}"#),
            .json(status: 400, #"{"error":"slow_down"}"#),
            .json(status: 400, #"{"error":"authorization_pending"}"#),
            .json(status: 200, GrokOIDCFixtures.tokenAnswer()),
            .json(status: 200, GrokOIDCFixtures.userInfo)
        ])
        let sleeps = Sleeps()

        let credentials = try await oidc.pollDeviceAuthorization(GrokOIDCFixtures.authorization()) { await sleeps.add($0) }

        #expect(credentials.accessToken == "access-1")
        // The email comes from `userinfo`, with no cookie involved.
        #expect(credentials.email == "someone@example.com")
        // `slow_down` adds five seconds and they stay added.
        #expect(await sleeps.intervals == [5, 10, 10])
        let form = try #require(GrokOIDCStub.forms(for: token).first)
        #expect(form["grant_type"] == "urn:ietf:params:oauth:grant-type:device_code")
        #expect(form["device_code"] == "device-1")
    }

    @Test func aFailedEmailLookupDoesNotCostTheApproval() async throws {
        let oidc = client("grok-oidc-no-email", [
            .json(status: 200, GrokOIDCFixtures.tokenAnswer()),
            .networkFailure
        ])
        let credentials = try await oidc.pollDeviceAuthorization(GrokOIDCFixtures.authorization()) { _ in }
        #expect(credentials.accessToken == "access-1")
        #expect(credentials.email == nil)
    }

    @Test(arguments: ["access_denied", "authorization_denied"])
    func aDenialEndsThePollAtOnce(code: String) async {
        let oidc = client("grok-oidc-denied-\(code)", [.json(status: 400, #"{"error":"\#(code)"}"#)])
        let sleeps = Sleeps()
        let error = await #expect(throws: GrokOIDCError.self) {
            _ = try await oidc.pollDeviceAuthorization(GrokOIDCFixtures.authorization()) { await sleeps.add($0) }
        }
        guard case .denied? = error else {
            Issue.record("expected denied, got \(String(describing: error))")
            return
        }
        #expect(await sleeps.intervals.isEmpty)
    }

    /// This used to read as "slow down" and spin silently until the code expired.
    @Test func anUnknownAnswerEndsThePollAtOnce() async {
        let oidc = client("grok-oidc-500", [.json(status: 500, #"{"error":"server_error"}"#)])
        let sleeps = Sleeps()
        let error = await #expect(throws: GrokOIDCError.self) {
            _ = try await oidc.pollDeviceAuthorization(GrokOIDCFixtures.authorization()) { await sleeps.add($0) }
        }
        guard case .invalidResponse? = error else {
            Issue.record("expected invalidResponse, got \(String(describing: error))")
            return
        }
        #expect(await sleeps.intervals.isEmpty)
    }

    @Test func anExpiredCodeEndsThePoll() async {
        let oidc = client("grok-oidc-expired", [.json(status: 400, #"{"error":"expired_token"}"#)])
        let error = await #expect(throws: GrokOIDCError.self) {
            _ = try await oidc.pollDeviceAuthorization(GrokOIDCFixtures.authorization()) { _ in }
        }
        guard case .expired? = error else {
            Issue.record("expected expired, got \(String(describing: error))")
            return
        }
    }

    /// A Wi-Fi blip during a sign-in that can take minutes must not end it.
    @Test func aNetworkFailureKeepsPolling() async throws {
        let oidc = client("grok-oidc-blip", [
            .networkFailure,
            .json(status: 200, GrokOIDCFixtures.tokenAnswer()),
            .json(status: 200, GrokOIDCFixtures.userInfo)
        ])
        let sleeps = Sleeps()
        let credentials = try await oidc.pollDeviceAuthorization(GrokOIDCFixtures.authorization()) { await sleeps.add($0) }
        #expect(credentials.accessToken == "access-1")
        #expect(await sleeps.intervals == [5])
    }

    @Test func aCancelledSleepStopsThePoll() async {
        let oidc = client("grok-oidc-cancel-sleep", [.json(status: 400, #"{"error":"authorization_pending"}"#)])
        await #expect(throws: CancellationError.self) {
            _ = try await oidc.pollDeviceAuthorization(GrokOIDCFixtures.authorization()) { _ in
                throw CancellationError()
            }
        }
    }

    /// Closing the window cancels the task. The real sleep is left in, so this proves the poll
    /// does not swallow the cancellation and run on until the code expires.
    @Test func closingTheWindowStopsThePoll() async {
        let oidc = client("grok-oidc-cancel", [.json(status: 400, #"{"error":"authorization_pending"}"#)])
        let task = Task {
            try await oidc.pollDeviceAuthorization(GrokOIDCFixtures.authorization(expiresIn: 600))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
