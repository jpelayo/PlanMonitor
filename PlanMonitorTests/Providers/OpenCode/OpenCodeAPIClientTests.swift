import Foundation
import Testing
@testable import PlanMonitor

/// One isolated client and request log per test, on the shared `StubURLProtocol`.
private struct OpenCodeTestClient {
    let token: String
    let client: OpenCodeAPIClient
    let session: URLSession

    init(_ token: String, status: Int = 200, json: String = OpenCodeFixtures.captured, headers: [String: String] = [:]) {
        self.token = token
        StubURLProtocol.setStub(.init(status: status, body: Data(json.utf8), headers: headers), for: token)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Case": token]
        self.session = URLSession(configuration: config)
        self.client = OpenCodeAPIClient(session: session)
    }

    var recorded: [URLRequest] { StubURLProtocol.requests(for: token) }
}

@Suite("OpenCode API client")
struct OpenCodeAPIClientTests {

    // MARK: - Decoding

    @Test func theDocsExampleDecodesToDollars() async throws {
        let stub = OpenCodeTestClient("opencode-docs", json: OpenCodeFixtures.docsExample)
        let rows = try await stub.client.fetchMemberBudgets(credential: OpenCodeFixtures.testKey)
        let member = try #require(rows.first?.member)

        #expect(member.userID == "user_alice")
        #expect(member.spent == OpenCodeFixtures.decimal("12.5"))
        #expect(member.budget == OpenCodeFixtures.decimal("75.25"))
        #expect(member.source == .custom)
        #expect(member.exceeded == false)
        #expect(member.resetsAt == OpenCodeFixtures.utc("2026-10-01T00:00:00Z"))
    }

    /// `null` is "no budget", never a $0 one.
    @Test func theCapturedAccountHasNoBudget() async throws {
        let stub = OpenCodeTestClient("opencode-captured")
        let rows = try await stub.client.fetchMemberBudgets(credential: OpenCodeFixtures.testKey)
        let member = try #require(rows.first?.member)

        #expect(member.budget == nil)
        #expect(member.source == nil)
        #expect(member.spent == 0)
        #expect(member.resetsAt == OpenCodeFixtures.utc("2026-11-01T00:00:00Z"))
    }

    @Test func plainNumbersAreAcceptedToo() async throws {
        let json = #"[{"user_id":"u","limit_micro_cents":7525000000,"spent_micro_cents":1250000000,"exceeded":false}]"#
        let stub = OpenCodeTestClient("opencode-numbers", json: json)
        let member = try #require(try await stub.client.fetchMemberBudgets(credential: OpenCodeFixtures.testKey).first?.member)

        #expect(member.budget == OpenCodeFixtures.decimal("75.25"))
        #expect(member.spent == OpenCodeFixtures.decimal("12.5"))
    }

    // MARK: - The request

    /// A key with Budgets › Write could change limits, so only GET is ever sent — and the key
    /// travels in the header alone, never in the URL.
    @Test func itSendsOneGetToTheBudgetsEndpointWithABearerKey() async throws {
        let stub = OpenCodeTestClient("opencode-request")
        _ = try await stub.client.fetchMemberBudgets(credential: OpenCodeFixtures.testKey)

        let request = try #require(stub.recorded.first)
        #expect(stub.recorded.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://opencode.ai/console/api/v1/budgets/members")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(OpenCodeFixtures.testKey)")
        #expect(request.url?.absoluteString.contains(OpenCodeFixtures.testKey) == false)
    }

    @Test func theStoredCredentialIsUsedWithoutAnOverride() async throws {
        let stub = OpenCodeTestClient("opencode-stored")
        await stub.client.setCredential(OpenCodeFixtures.testKey)
        _ = try await stub.client.fetchMemberBudgets()

        #expect(stub.recorded.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(OpenCodeFixtures.testKey)")
    }

    @Test func noCredentialSendsNothing() async {
        let stub = OpenCodeTestClient("opencode-none")
        await #expect(throws: OpenCodeAPIError.noCredential) {
            try await stub.client.fetchMemberBudgets()
        }
        #expect(stub.recorded.isEmpty)
    }

    // MARK: - Errors

    @Test func statusCodesMapToErrors() async {
        let cases: [(Int, [String: String], OpenCodeAPIError)] = [
            (401, [:], .unauthorized),
            (403, [:], .missingScope),
            (404, [:], .invalidResponse(endpoint: OpenCodeAPIClient.budgetsPath, statusCode: 404)),
            (429, ["Retry-After": "30"], .rateLimited(retryAfter: 30)),
            (500, [:], .invalidResponse(endpoint: OpenCodeAPIClient.budgetsPath, statusCode: 500))
        ]
        for (status, headers, expected) in cases {
            let stub = OpenCodeTestClient("opencode-status-\(status)", status: status, json: "{}", headers: headers)
            await #expect(throws: expected) {
                try await stub.client.fetchMemberBudgets(credential: OpenCodeFixtures.testKey)
            }
        }
    }

    /// Only a refusal of the key itself is definitive; everything else backs off and keeps the
    /// cached figures.
    @Test func onlyKeyRefusalsAreDefinitive() {
        #expect(!OpenCodeAPIError.unauthorized.isTransient)
        #expect(!OpenCodeAPIError.missingScope.isTransient)
        #expect(!OpenCodeAPIError.noCredential.isTransient)
        #expect(OpenCodeAPIError.rateLimited(retryAfter: nil).isTransient)
        #expect(OpenCodeAPIError.network("offline").isTransient)
        #expect(OpenCodeAPIError.invalidResponse(endpoint: "/", statusCode: 404).isTransient)
        #expect(OpenCodeAPIError.invalidPayload(endpoint: "/", reason: "shape").isTransient)
    }

    // MARK: - Go usage

    @Test func goUsageIsOneGetToTheInferenceBackend() async throws {
        let stub = OpenCodeTestClient("opencode-go", json: OpenCodeFixtures.goUsage)
        let go = try await stub.client.fetchGoUsage(credential: OpenCodeFixtures.testKey)

        #expect(go?.weekly?.resetsAt == OpenCodeFixtures.utc("2026-10-26T00:00:00Z"))
        let request = try #require(stub.recorded.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://opencode.ai/inference/go/v1/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(OpenCodeFixtures.testKey)")
    }

    /// A key without Usage, or a workspace without Go, is "no Go here" — never an error that could
    /// blank the budget half.
    @Test func goUsageThatCannotBeReadIsNil() async throws {
        let forbidden = OpenCodeTestClient("opencode-go-403", status: 403, json: #"{"_tag":"Forbidden"}"#)
        #expect(try await forbidden.client.fetchGoUsage(credential: OpenCodeFixtures.testKey) == nil)

        let missing = OpenCodeTestClient("opencode-go-404", status: 404, json: "{}")
        #expect(try await missing.client.fetchGoUsage(credential: OpenCodeFixtures.testKey) == nil)
    }

    @Test func aRefusedKeyIsStillAnErrorOnGoUsage() async {
        let stub = OpenCodeTestClient("opencode-go-401", status: 401, json: "{}")
        await #expect(throws: OpenCodeAPIError.unauthorized) {
            try await stub.client.fetchGoUsage(credential: OpenCodeFixtures.testKey)
        }
    }

    @Test func aMalformedBodyIsAPayloadError() async {
        let stub = OpenCodeTestClient("opencode-malformed", json: #"{"members":[]}"#)
        do {
            _ = try await stub.client.fetchMemberBudgets(credential: OpenCodeFixtures.testKey)
            Issue.record("expected a payload error")
        } catch OpenCodeAPIError.invalidPayload {
            // expected
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}
