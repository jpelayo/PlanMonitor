import Foundation

nonisolated enum OpenRouterAPIError: Error, LocalizedError, Equatable {
    case noCredential
    case unauthorized
    case notAManagementKey
    case guardrailsUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case network(String)
    case invalidResponse(endpoint: String, statusCode: Int)
    case invalidPayload(endpoint: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .noCredential:
            String(localized: "Not connected. Add an OpenRouter management key.")
        case .unauthorized:
            String(localized: "This key was revoked or is no longer valid.")
        case .notAManagementKey:
            String(localized: "That looks like an inference key. PlanMonitor needs a management key.")
        case .guardrailsUnavailable:
            String(localized: "Guardrails are not available for this account.")
        case .rateLimited:
            String(localized: "OpenRouter is rate limiting requests. Backing off.")
        case .network(let reason):
            String(localized: "Network error: \(reason)")
        case .invalidResponse(_, let statusCode):
            String(localized: "Unexpected response from OpenRouter (HTTP \(statusCode)).")
        case .invalidPayload(_, let reason):
            String(localized: "OpenRouter changed its response format: \(reason)")
        }
    }

    /// Transient failures keep the cached snapshot and back off; definitive ones don't.
    var isTransient: Bool {
        switch self {
        case .network, .rateLimited, .invalidResponse: true
        default: false
        }
    }
}

/// Read-only client for the OpenRouter management API.
///
/// Structurally incapable of mutation: `request` hardcodes GET and there is no method
/// parameter anywhere. A management key can delete API keys and guardrails, so this is
/// enforced by construction rather than by discipline. See build plan §15.
actor OpenRouterAPIClient {
    private static let host = "openrouter.ai"
    private static let base = URL(string: "https://openrouter.ai/api/v1")!
    private static let maxResponseBytes = 8 * 1024 * 1024
    private static let pageSize = 100
    private static let maxPages = 20

    private let session: URLSession
    private let decoder: JSONDecoder
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
        self.decoder = JSONDecoder()
    }

    private static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "PlanMonitor-for-OpenRouter/\(version) (macOS)"
    }

    func setCredential(_ key: String?) {
        credential = key
    }

    // MARK: - Endpoints

    /// Validates a key without storing it. Used by the connect flow.
    func validateKey(_ key: String) async throws -> KeyIdentity {
        let dto: DataEnvelope<CurrentKeyDTO> = try await request(path: "/key", credential: key)
        guard dto.data.hasManagementCapability else {
            throw OpenRouterAPIError.notAManagementKey
        }
        return KeyIdentity(
            label: dto.data.label ?? String(localized: "OpenRouter key"),
            isManagementKey: true,
            isFreeTier: dto.data.isFreeTier ?? false,
            expiresAt: dto.data.expiresAt.flatMap(ISO8601DateParser.date(from:))
        )
    }

    func fetchCredits() async throws -> CreditsDTO {
        let envelope: DataEnvelope<CreditsDTO> = try await request(path: "/credits")
        return envelope.data
    }

    func fetchKeys() async throws -> [APIKeyDTO] {
        try await paginate(path: "/keys", query: [URLQueryItem(name: "include_disabled", value: "true")])
    }

    func fetchGuardrails() async throws -> [GuardrailDTO] {
        do {
            return try await paginate(path: "/guardrails", query: [])
        } catch OpenRouterAPIError.notAManagementKey {
            // A 403 on this endpoint means a personal account, not a bad key.
            throw OpenRouterAPIError.guardrailsUnavailable
        }
    }

    /// Per-minute spend and token counts by model, for the last `minutes` minutes.
    ///
    /// This is the client's **only** non-GET call. `/analytics/query` is a read that
    /// uses POST because the query does not fit in a URL — it creates, updates and
    /// deletes nothing. The path is hardcoded rather than parameterised so this cannot
    /// grow into a general POST primitive; the read-only guarantee in §15 of the plan
    /// is preserved by construction, and asserted by test.
    func queryRecentUsage(minutes: Int, now: Date = Date()) async throws -> [AnalyticsRowDTO] {
        try await queryUsage(minutes: minutes, granularity: "minute", byModel: true, now: now)
    }

    /// Rolling 24-hour spend. Hourly buckets rather than minute ones: 24 hours at
    /// minute granularity would be ~1440 buckets per model and could hit the row cap,
    /// and nothing here needs sub-hour resolution.
    func queryLast24Hours(now: Date = Date()) async throws -> [AnalyticsRowDTO] {
        // Grouped by model so this one call also feeds the recent-models section for
        // windows longer than an hour. 24 hourly buckets per model stays far under the
        // row cap.
        try await queryUsage(minutes: 24 * 60, granularity: "hour", byModel: true, now: now)
    }

    private func queryUsage(
        minutes: Int,
        granularity: String,
        byModel: Bool,
        now: Date
    ) async throws -> [AnalyticsRowDTO] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        var body: [String: Any] = [
            "metrics": ["total_usage", "tokens_total", "request_count"],
            "granularity": granularity,
            "time_range": [
                "start": formatter.string(from: now.addingTimeInterval(-Double(minutes) * 60)),
                "end": formatter.string(from: now)
            ],
            "limit": 1000
        ]
        if byModel { body["dimensions"] = ["model"] }
        let envelope: AnalyticsEnvelope = try await postAnalyticsQuery(body: body)
        return envelope.data.data
    }

    /// Spend over the last 30 completed UTC days. Excludes today by design of the
    /// endpoint, so callers add today's figure from the live key counters.
    func fetchActivity() async throws -> [ActivityRowDTO] {
        let envelope: DataEnvelope<[ActivityRowDTO]> = try await request(path: "/activity")
        return envelope.data
    }

    func fetchGuardrailKeyAssignments() async throws -> [GuardrailKeyAssignmentDTO] {
        do {
            return try await paginate(path: "/guardrails/assignments/keys", query: [])
        } catch OpenRouterAPIError.notAManagementKey {
            throw OpenRouterAPIError.guardrailsUnavailable
        }
    }

    // MARK: - Transport

    /// Walks `offset` until a short page arrives. Bounded by `maxPages` so a
    /// pathological account cannot hang a poll indefinitely.
    private func paginate<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> [T] {
        var results: [T] = []
        var offset = 0
        for _ in 0..<Self.maxPages {
            var items = query
            items.append(URLQueryItem(name: "limit", value: String(Self.pageSize)))
            items.append(URLQueryItem(name: "offset", value: String(offset)))
            let page: DataEnvelope<[T]> = try await request(path: path, query: items)
            results.append(contentsOf: page.data)
            if page.data.count < Self.pageSize { return results }
            offset += Self.pageSize
        }
        return results
    }

    /// Deliberately takes no path or method: both are fixed. Adding either as a
    /// parameter would turn this into a general write primitive.
    private func postAnalyticsQuery<T: Decodable & Sendable>(body: [String: Any]) async throws -> T {
        guard let token = credential else { throw OpenRouterAPIError.noCredential }

        let url = Self.base.appendingPathComponent("analytics/query")
        guard url.host == Self.host else {
            throw OpenRouterAPIError.invalidResponse(endpoint: "/analytics/query", statusCode: -1)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenRouterAPIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterAPIError.invalidResponse(endpoint: "/analytics/query", statusCode: -1)
        }
        try Self.validate(status: http, endpoint: "/analytics/query")
        guard data.count <= Self.maxResponseBytes else {
            throw OpenRouterAPIError.invalidPayload(endpoint: "/analytics/query", reason: "response too large")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OpenRouterAPIError.invalidPayload(endpoint: "/analytics/query", reason: String(describing: error))
        }
    }

    private static func validate(status http: HTTPURLResponse, endpoint: String) throws {
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw OpenRouterAPIError.unauthorized
        case 403:
            throw OpenRouterAPIError.notAManagementKey
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw OpenRouterAPIError.rateLimited(retryAfter: retry)
        default:
            throw OpenRouterAPIError.invalidResponse(endpoint: endpoint, statusCode: http.statusCode)
        }
    }

    private func request<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        credential overrideCredential: String? = nil
    ) async throws -> T {
        guard let token = overrideCredential ?? credential else {
            throw OpenRouterAPIError.noCredential
        }

        var components = URLComponents(
            url: Self.base.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url, url.host == Self.host else {
            throw OpenRouterAPIError.invalidResponse(endpoint: path, statusCode: -1)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"                       // the only method this client speaks
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenRouterAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterAPIError.invalidResponse(endpoint: path, statusCode: -1)
        }

        try Self.validate(status: http, endpoint: path)

        guard data.count <= Self.maxResponseBytes else {
            throw OpenRouterAPIError.invalidPayload(endpoint: path, reason: "response too large")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OpenRouterAPIError.invalidPayload(endpoint: path, reason: String(describing: error))
        }
    }
}

/// Ported from the Claude variant: OpenRouter timestamps vary by endpoint, so try
/// fractional seconds, then plain internet date-time, before giving up.
nonisolated enum ISO8601DateParser {
    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
