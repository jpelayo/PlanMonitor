import Foundation
import Testing
@testable import PlanMonitor

/// One isolated client and request log per test, on `StubURLProtocol` (`OpenRouterAPIClientTests`).
private struct StubbedClient {
    let token: String
    let client: ClaudePlatformClient

    init(_ token: String, status: Int = 200, json: String = "{}", headers: [String: String] = [:]) {
        self.token = token
        StubURLProtocol.setStub(.init(status: status, body: Data(json.utf8), headers: headers), for: token)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Case": token]
        self.client = ClaudePlatformClient(configuration: config)
    }

    var recorded: [URLRequest] { StubURLProtocol.requests(for: token) }
}

@Suite("Claude-API client")
struct ClaudePlatformClientTests {
    private let org = ClaudePlatformFixtures.organizationID

    // MARK: - Decoding the captured responses

    @Test func prepaidCreditsDecodeWithNullsKeptAsNil() throws {
        let credits = try ClaudePlatformFixtures.decode(
            ClaudePlatformPrepaidCreditsResponse.self, ClaudePlatformFixtures.prepaidCredits
        )
        #expect(credits.amount == 19_955)
        #expect(credits.currency == "USD")
        #expect(credits.balance?.credits?.exponent == 2)
        #expect(credits.amountWithoutScopedCredits == 0)
        #expect(credits.pendingInvoiceAmountCents == nil)
        #expect(credits.tranches?.isEmpty == true)
        #expect(credits.promoTranches?.count == 1)
        #expect(credits.promoTranches?.first?.remainingAmountMinorUnits == 19_954)
        #expect(credits.promoTranches?.first?.grantedAmountMinorUnits == 20_000)
        #expect(credits.promoTranches?.first?.name == "API credit (Max 20x)")
    }

    @Test func spendLimitsAndCurrentSpendDecode() throws {
        let limits = try ClaudePlatformFixtures.decode(
            ClaudePlatformSpendLimitsResponse.self, ClaudePlatformFixtures.spendLimits
        )
        #expect(limits.enforcedLimitUsd == 50_000)
        #expect(limits.spendLimits?.map(\.limitUsd) == [19_500, 20_000])
        #expect(limits.spendLimits?.map(\.limitAction) == ["notify_only", "notify_and_pause"])

        let spend = try ClaudePlatformFixtures.decode(
            ClaudePlatformCurrentSpendResponse.self, ClaudePlatformFixtures.currentSpend
        )
        #expect(spend.amount == 46)
        #expect(spend.resetsAt == "2026-11-01T00:00:00Z")
    }

    @Test func autoRechargeDecodes() throws {
        let recharge = try ClaudePlatformFixtures.decode(
            ClaudePlatformAutoRechargeResponse.self, ClaudePlatformFixtures.autoRecharge
        )
        #expect(recharge.status == "disabled")
        #expect(recharge.targetAmount == 1_500)
        #expect(recharge.thresholdAmount == 500)
    }

    // MARK: - Requests

    @Test func billingRequestsCarryTheSessionAndHitPlatform() async throws {
        let stub = StubbedClient("claudeapi-credits", json: ClaudePlatformFixtures.prepaidCredits)
        await stub.client.setSessionCookies("sessionKey=abc; __cf_bm=edge")

        let credits = try await stub.client.fetchPrepaidCredits(organizationID: org)

        #expect(credits.amount == 19_955)
        let request = try #require(stub.recorded.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://platform.claude.com/api/organizations/\(org)/prepaid/credits")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "__cf_bm=edge; sessionKey=abc")
    }

    @Test func everyEndpointIsAGetUnderItsOrganization() async throws {
        let stub = StubbedClient("claudeapi-paths", json: "{}")
        await stub.client.setSessionCookies("sessionKey=abc")

        _ = try await stub.client.fetchCurrentSpend(organizationID: org)
        _ = try await stub.client.fetchSpendLimits(organizationID: org)
        _ = try await stub.client.fetchAutoRecharge(organizationID: org)

        #expect(stub.recorded.map { $0.url?.path } == [
            "/api/organizations/\(org)/current_spend",
            "/api/organizations/\(org)/spend_limits",
            "/api/organizations/\(org)/prepaid/auto_recharge"
        ])
        #expect(stub.recorded.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func noSessionFailsBeforeAnyRequest() async {
        let stub = StubbedClient("claudeapi-no-session")
        do {
            _ = try await stub.client.fetchCurrentSpend(organizationID: org)
            Issue.record("expected noSessionCookies")
        } catch ClaudePlatformClient.APIError.noSessionCookies {
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(stub.recorded.isEmpty)
    }

    @Test func unauthorizedStatusIsUnauthorized() async {
        let stub = StubbedClient("claudeapi-401", status: 401, json: #"{"error":"x"}"#)
        await stub.client.setSessionCookies("sessionKey=expired")
        do {
            _ = try await stub.client.fetchCurrentSpend(organizationID: org)
            Issue.record("expected unauthorized")
        } catch ClaudePlatformClient.APIError.unauthorized {
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    // MARK: - Identity

    /// Measured: signed out, `/api/bootstrap` answers 200 with `"account": null`. That explicit
    /// answer — and only that — is a rejection.
    @Test func signedOutBootstrapIsUnauthorized() async {
        let stub = StubbedClient("claudeapi-bootstrap-null", json: #"{"account":null,"statsig":{}}"#)
        await stub.client.setSessionCookies("activitySessionId=pre-login")
        do {
            _ = try await stub.client.fetchIdentity()
            Issue.record("expected unauthorized")
        } catch ClaudePlatformClient.APIError.unauthorized {
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    /// A 200 with a body we do not recognise is transient by the house rule — never a sign-out.
    @Test func unrecognisedBootstrapIsTransient() async {
        let stub = StubbedClient("claudeapi-bootstrap-odd", json: #"{"maintenance":true}"#)
        await stub.client.setSessionCookies("sessionKey=abc")
        do {
            _ = try await stub.client.fetchIdentity()
            Issue.record("expected malformedResponse")
        } catch IdentityError.malformedResponse {
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func identityPrefersTheAPIOrganization() async throws {
        let bootstrap = #"""
        {"account":{"email_address":"someone@example.com","memberships":[
          {"organization":{"uuid":"chat-org","name":"Chat","capabilities":["chat","claude_max"]}},
          {"organization":{"uuid":"console-org","name":"Console","capabilities":["api"]}}
        ]}}
        """#
        let stub = StubbedClient("claudeapi-bootstrap", json: bootstrap)
        await stub.client.setSessionCookies("sessionKey=abc")

        let identity = try await stub.client.fetchIdentity()

        #expect(identity.email == "someone@example.com")
        #expect(identity.preferredOrganization?.id == "console-org")
        #expect(identity.preferredOrganization?.name == "Console")
    }

    // MARK: - Rotation

    /// A console session rotates: whatever the server sets is folded into the header the
    /// authentication service then writes back to the Keychain.
    @Test func rotatedCookiesAreAbsorbed() async throws {
        let stub = StubbedClient(
            "claudeapi-rotate",
            json: ClaudePlatformFixtures.currentSpend,
            headers: ["Set-Cookie": "sessionKey=rotated; Path=/; Secure; HttpOnly"]
        )
        await stub.client.setSessionCookies("sessionKey=original; __cf_bm=edge")

        _ = try await stub.client.fetchCurrentSpend(organizationID: org)

        #expect(await stub.client.currentSessionCookies() == "__cf_bm=edge; sessionKey=rotated")
    }
}
