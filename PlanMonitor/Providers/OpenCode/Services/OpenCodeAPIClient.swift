import Foundation

nonisolated enum OpenCodeAPIError: Error, LocalizedError, Equatable {
    case noCredential
    /// Revoked, expired, or never valid. Keys can be created with a 1-, 7- or 30-day expiry.
    case unauthorized
    /// A real key that may read neither budgets nor Go usage. A 403 from one endpoint alone only
    /// hides that half.
    case missingScope
    case rateLimited(retryAfter: TimeInterval?)
    case network(String)
    case invalidResponse(endpoint: String, statusCode: Int)
    case invalidPayload(endpoint: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .noCredential:
            String(localized: "Not connected. Add an OpenCode API key.")
        case .unauthorized:
            String(localized: "This key was revoked, has expired or is not valid.")
        case .missingScope:
            String(localized: "This key can read neither Go usage nor budgets. Give it Usage › Read and Budgets › Read in the OpenCode Console.")
        case .rateLimited:
            String(localized: "OpenCode is rate limiting requests. Backing off.")
        case .network(let reason):
            String(localized: "Network error: \(reason)")
        case .invalidResponse(_, let statusCode):
            String(localized: "Unexpected response from OpenCode (HTTP \(statusCode)).")
        case .invalidPayload(_, let reason):
            String(localized: "OpenCode changed its response format: \(reason)")
        }
    }

    /// Transient failures keep the cached snapshot and back off; definitive ones mean the key
    /// itself must change.
    var isTransient: Bool {
        switch self {
        case .network, .rateLimited, .invalidResponse, .invalidPayload: true
        case .noCredential, .unauthorized, .missingScope: false
        }
    }
}

/// Read-only client for the two things a Console key can read (probed 2026-10-22):
///
/// - `GET https://opencode.ai/inference/go/v1/usage` — the Go subscription's three windows. The old
///   open-source console routed `GET /zen/go/v1/usage` here (`inference-proxy.ts`), with the key as
///   a Bearer token, `oc_sk_` keys included.
/// - `GET https://opencode.ai/console/api/v1/budgets/members` — this month's spend and budget.
///
/// The credit balance is not readable: `inference/v1/usage` and `inference/v1/balance` are 404.
///
/// Structurally incapable of mutation: `request` hardcodes GET and takes no method. A key with
/// Budgets › Write could change limits, so this is enforced by construction. The key travels only
/// in the `Authorization` header — never in a URL, a log, or a snapshot.
actor OpenCodeAPIClient {
    private static let host = "opencode.ai"
    private static let budgetsURL = URL(string: "https://opencode.ai/console/api/v1/budgets/members")!
    private static let goUsageURL = URL(string: "https://opencode.ai/inference/go/v1/usage")!
    private static let maxResponseBytes = 2 * 1024 * 1024
    static let budgetsPath = "/budgets/members"
    static let goUsagePath = "/go/v1/usage"

    private let session: URLSession
    private let decoder = JSONDecoder()
    private var credential: String?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": Self.userAgent
            ]
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.httpCookieAcceptPolicy = .never
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config)
        }
    }

    private static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "PlanMonitor/\(version) (macOS)"
    }

    func setCredential(_ key: String?) {
        credential = key
    }

    /// Every member's monthly budget. With `credential`, validates a candidate key without
    /// storing it — the connect flow.
    func fetchMemberBudgets(credential overrideCredential: String? = nil) async throws -> [OpenCodeMemberBudgetDTO] {
        try await request(url: Self.budgetsURL, endpoint: Self.budgetsPath, credential: overrideCredential)
    }

    /// The Go windows, or `nil` when this key or workspace has none to read: a 403 (no Usage scope)
    /// or a 404 is "Go is not here", not a failure. A 401 still throws — the key itself is refused.
    func fetchGoUsage(credential overrideCredential: String? = nil) async throws -> OpenCodeGoUsage? {
        do {
            let response: OpenCodeGoUsageResponse = try await request(
                url: Self.goUsageURL,
                endpoint: Self.goUsagePath,
                credential: overrideCredential
            )
            return response.goUsage
        } catch OpenCodeAPIError.missingScope {
            return nil
        } catch OpenCodeAPIError.invalidResponse(endpoint: _, statusCode: 404) {
            return nil
        }
    }

    // MARK: - Transport

    private static func validate(status http: HTTPURLResponse, endpoint: String) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw OpenCodeAPIError.unauthorized
        case 403:
            throw OpenCodeAPIError.missingScope
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw OpenCodeAPIError.rateLimited(retryAfter: retry)
        default:
            throw OpenCodeAPIError.invalidResponse(endpoint: endpoint, statusCode: http.statusCode)
        }
    }

    private func request<T: Decodable & Sendable>(
        url: URL,
        endpoint path: String,
        credential overrideCredential: String?
    ) async throws -> T {
        guard let token = overrideCredential ?? credential else {
            throw OpenCodeAPIError.noCredential
        }
        guard url.host == Self.host, url.scheme == "https" else {
            throw OpenCodeAPIError.invalidResponse(endpoint: path, statusCode: -1)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"                       // the only method this client speaks
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenCodeAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenCodeAPIError.invalidResponse(endpoint: path, statusCode: -1)
        }
        try Self.validate(status: http, endpoint: path)

        guard data.count <= Self.maxResponseBytes else {
            throw OpenCodeAPIError.invalidPayload(endpoint: path, reason: "response too large")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OpenCodeAPIError.invalidPayload(endpoint: path, reason: String(describing: error))
        }
    }
}
