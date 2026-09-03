import Foundation
import Testing
@testable import PlanTracker

/// Replays canned responses and records outbound requests.
///
/// Tests run in parallel, so responses are keyed by a per-test token carried in
/// `X-Test-Case` (injected via the session's `httpAdditionalHeaders`). A single shared
/// responder would race — which is exactly what happened before this was keyed.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) private static var log: [String: [URLRequest]] = [:]

    static func setStub(_ stub: Stub, for token: String) {
        lock.lock(); stubs[token] = stub; lock.unlock()
    }

    static func requests(for token: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return log[token] ?? []
    }

    private static func record(_ request: URLRequest, token: String) {
        lock.lock(); log[token, default: []].append(request); lock.unlock()
    }

    private static func stub(for token: String) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        return stubs[token]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "X-Test-Case") ?? ""
        Self.record(request, token: token)
        let stub = Self.stub(for: token) ?? Stub(status: 200, body: Data("{}".utf8), headers: [:])
        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// One isolated client + request log per test.
private struct TestClient {
    let token: String
    let client: OpenRouterAPIClient

    init(_ token: String, status: Int = 200, json: String = "{}", headers: [String: String] = [:]) {
        self.token = token
        StubURLProtocol.setStub(
            .init(status: status, body: Data(json.utf8), headers: headers), for: token
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Case": token]
        self.client = OpenRouterAPIClient(session: URLSession(configuration: config))
    }

    func respond(status: Int, json: String, headers: [String: String] = [:]) {
        StubURLProtocol.setStub(
            .init(status: status, body: Data(json.utf8), headers: headers), for: token
        )
    }

    var recorded: [URLRequest] { StubURLProtocol.requests(for: token) }
}

@Suite("API client")
struct APIClientTests {

    /// Build plan §15: a management key can delete keys and guardrails, so the client
    /// must be *structurally* incapable of mutation — not merely disinclined.
    ///
    /// One endpoint breaks the all-GET rule: `/analytics/query` is a read that uses
    /// POST because the query will not fit in a URL. The guarantee is therefore
    /// "GET everywhere, except a POST to exactly that one path" — asserted here so the
    /// exception cannot quietly widen.
    @Test("Every request is a GET, except the analytics query")
    func onlyEverIssuesGET() async throws {
        let t = TestClient("get-only", json: #"{"data":[]}"#)
        await t.client.setCredential("sk-or-v1-test")

        t.respond(status: 200, json: #"{"data":{"total_credits":10,"total_usage":1}}"#)
        _ = try? await t.client.fetchCredits()
        t.respond(status: 200, json: #"{"data":[]}"#)
        _ = try? await t.client.fetchKeys()
        _ = try? await t.client.fetchGuardrails()
        _ = try? await t.client.fetchGuardrailKeyAssignments()
        t.respond(status: 200, json: #"{"data":{"label":"sk-or-v1-x","is_management_key":true}}"#)
        _ = try? await t.client.validateKey("sk-or-v1-test")

        t.respond(status: 200, json: #"{"data":{"data":[],"metadata":{"row_count":0}}}"#)
        _ = try? await t.client.queryRecentUsage(minutes: 60)

        #expect(t.recorded.count >= 6)
        for request in t.recorded {
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                #expect(path.hasSuffix("/analytics/query"),
                        "POST escaped to an unexpected path: \(path)")
            } else {
                #expect(request.httpMethod == "GET",
                        "unexpected method \(request.httpMethod ?? "nil") on \(path)")
                #expect(request.httpBody == nil)
            }
        }
        // Exactly one POST, and it is the analytics read.
        let posts = t.recorded.filter { $0.httpMethod == "POST" }
        #expect(posts.count == 1)
        #expect(posts.first?.url?.path.hasSuffix("/analytics/query") == true)
    }

    @Test("Analytics query sends a minute-granularity window with the model dimension")
    func analyticsQueryShape() async throws {
        let t = TestClient("analytics-shape",
                           json: #"{"data":{"data":[],"metadata":{"row_count":0}}}"#)
        await t.client.setCredential("sk-or-v1-test")
        _ = try? await t.client.queryRecentUsage(minutes: 60)

        let request = try #require(t.recorded.first { $0.httpMethod == "POST" })
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // URLProtocol moves the body to the stream, so read it back from there.
        let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(contentsOf: buffer[0..<read])
            }
            return data
        } ?? Data()
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["granularity"] as? String == "minute")
        #expect((json["dimensions"] as? [String]) == ["model"])
        let metrics = try #require(json["metrics"] as? [String])
        #expect(metrics.contains("total_usage"))
        #expect(metrics.contains("tokens_total"))
        #expect(json["time_range"] is [String: Any])
    }

    @Test("Requests go only to openrouter.ai over https, with a bearer token")
    func hostAndAuth() async throws {
        let t = TestClient("host-auth", json: #"{"data":{"total_credits":10,"total_usage":1}}"#)
        await t.client.setCredential("sk-or-v1-secret")
        _ = try? await t.client.fetchCredits()

        let request = try #require(t.recorded.first)
        #expect(request.url?.host == "openrouter.ai")
        #expect(request.url?.scheme == "https")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-v1-secret")
    }

    @Test("401 maps to unauthorized — a revoked key, not a stale session")
    func unauthorized() async {
        let t = TestClient("401", status: 401, json: #"{"error":"nope"}"#)
        await t.client.setCredential("sk-or-v1-test")
        await #expect(throws: OpenRouterAPIError.unauthorized) { try await t.client.fetchCredits() }
    }

    /// The most likely setup mistake. A raw 403 would be a terrible thing to show.
    @Test("403 on /credits maps to notAManagementKey")
    func inferenceKeyPasted() async {
        let t = TestClient("403-credits", status: 403, json: #"{"error":"management keys only"}"#)
        await t.client.setCredential("sk-or-v1-inference")
        await #expect(throws: OpenRouterAPIError.notAManagementKey) { try await t.client.fetchCredits() }
    }

    /// Personal accounts have no guardrails. That must degrade the section to absent,
    /// not report a bad key. Build plan §6.5.
    @Test("403 on /guardrails maps to guardrailsUnavailable, not a bad key")
    func personalAccountGuardrails() async {
        let t = TestClient("403-guardrails", status: 403, json: #"{"error":"forbidden"}"#)
        await t.client.setCredential("sk-or-v1-test")
        await #expect(throws: OpenRouterAPIError.guardrailsUnavailable) {
            try await t.client.fetchGuardrails()
        }
    }

    @Test("A key without management capability is rejected before it is stored")
    func validateRejectsInferenceKey() async {
        let t = TestClient("validate-reject",
                           json: #"{"data":{"label":"sk-or-v1-x","is_management_key":false}}"#)
        await #expect(throws: OpenRouterAPIError.notAManagementKey) {
            try await t.client.validateKey("sk-or-v1-x")
        }
    }

    @Test("Legacy accounts reporting is_provisioning_key still validate")
    func legacyProvisioningFlag() async throws {
        let t = TestClient("validate-legacy",
                           json: #"{"data":{"label":"sk-or-v1-x","is_provisioning_key":true}}"#)
        let identity = try await t.client.validateKey("sk-or-v1-x")
        #expect(identity.isManagementKey)
    }

    @Test("429 surfaces Retry-After so the poller can honour it")
    func rateLimited() async {
        let t = TestClient("429", status: 429, json: "{}", headers: ["Retry-After": "42"])
        await t.client.setCredential("sk-or-v1-test")
        await #expect(throws: OpenRouterAPIError.rateLimited(retryAfter: 42)) {
            try await t.client.fetchCredits()
        }
    }

    @Test("Rate limiting and network errors are transient; bad credentials are not")
    func transienceClassification() {
        #expect(OpenRouterAPIError.rateLimited(retryAfter: nil).isTransient)
        #expect(OpenRouterAPIError.network("offline").isTransient)
        #expect(OpenRouterAPIError.invalidResponse(endpoint: "/keys", statusCode: 503).isTransient)
        #expect(!OpenRouterAPIError.unauthorized.isTransient)
        #expect(!OpenRouterAPIError.notAManagementKey.isTransient)
    }

    @Test("Malformed JSON is reported as a payload problem, not a crash")
    func malformedPayload() async {
        let t = TestClient("malformed", json: "{ this is not json")
        await t.client.setCredential("sk-or-v1-test")
        await #expect(throws: OpenRouterAPIError.self) { try await t.client.fetchCredits() }
    }

    @Test("Missing credential fails before any request is made")
    func noCredential() async {
        let t = TestClient("no-cred")
        await #expect(throws: OpenRouterAPIError.noCredential) { try await t.client.fetchCredits() }
        #expect(t.recorded.isEmpty)
    }

    @Test("Pagination stops on a short page and passes limit/offset")
    func paginationStopsOnShortPage() async throws {
        let t = TestClient("paginate",
                           json: #"{"data":[{"id":"g1","limit_usd":10,"reset_interval":"daily"}]}"#)
        await t.client.setCredential("sk-or-v1-test")
        let guardrails = try await t.client.fetchGuardrails()
        #expect(guardrails.count == 1)
        #expect(t.recorded.count == 1)          // one short page means one request
        let query = try #require(t.recorded.first?.url?.query)
        #expect(query.contains("limit=100"))
        #expect(query.contains("offset=0"))
    }
}
