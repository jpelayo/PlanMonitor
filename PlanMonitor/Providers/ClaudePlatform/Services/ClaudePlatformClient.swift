import Foundation

/// The Claude Platform console's own JSON API at `platform.claude.com`, authenticated by the
/// browser session harvested at login. An API key cannot read any of this — every key kind answers
/// `403 account_session_invalid` (plan §1.3) — so a session is the only path.
///
/// Request scaffold from `ClaudeAPIClient`; cookie rotation from `OpenAIAPIClient`, because a
/// console session is the kind that rotates: every response's `Set-Cookie` is folded back into the
/// header, which the authentication service writes to the Keychain after each good poll. The
/// session never touches a shared cookie jar.
actor ClaudePlatformClient {
    private let baseURL = URL(string: "https://platform.claude.com")!
    private let session: URLSession
    private var sessionCookies: String?
    private var sessionCookieValues: [String: String] = [:]

    enum APIError: Error, LocalizedError {
        case unauthorized
        case forbidden
        case networkError(Error)
        case invalidResponse(endpoint: String, statusCode: Int?, bodyPreview: String?)
        case decodingError(Error)
        case noSessionCookies
        case organizationUnavailable

        /// Unlocalized, as every other provider's `APIError` is.
        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Session expired. Please sign in again."
            case .forbidden:
                "Access denied. Please sign in again."
            case .networkError(let error):
                "Network error: \(error.localizedDescription)"
            case .invalidResponse(let endpoint, let statusCode, _):
                if let statusCode {
                    "Invalid response from server for \(endpoint) (HTTP \(statusCode))."
                } else {
                    "Invalid response from server for \(endpoint)."
                }
            case .decodingError(let error):
                "Failed to parse response: \(error.localizedDescription)"
            case .noSessionCookies:
                "Not authenticated. Please sign in."
            case .organizationUnavailable:
                "No Claude Platform organization was found for this account."
            }
        }
    }

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration
        config.httpAdditionalHeaders = (config.httpAdditionalHeaders ?? [:]).merging([
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            "Origin": "https://platform.claude.com",
            "Referer": "https://platform.claude.com/"
        ]) { existing, _ in existing }
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - Session cookies

    func setSessionCookies(_ cookies: String) {
        sessionCookieValues = Self.parseCookieHeader(cookies)
        sessionCookies = Self.serializeCookieHeader(sessionCookieValues)
    }

    func clearSessionCookies() {
        sessionCookies = nil
        sessionCookieValues.removeAll()
    }

    func currentSessionCookies() -> String? {
        sessionCookies
    }

    // MARK: - Identity

    /// Who the session belongs to and which orgs it can read. `/api/bootstrap` answers 200 with
    /// `"account": null` when signed out, which is mapped to `.unauthorized` — that is the console's
    /// own explicit statement, not a guess. Any other unexpected shape is transient.
    func fetchIdentity() async throws -> ClaudePlatformIdentity {
        let json = try await getJSON("/api/bootstrap")
        ClaudePlatformDiagnostics.log(ClaudePlatformDiagnostics.describeBootstrap(json))
        switch ClaudePlatformIdentityParser.parseBootstrap(json) {
        case .signedOut:
            throw APIError.unauthorized
        case .malformed:
            throw IdentityError.malformedResponse
        case .identity(let identity) where !identity.organizations.isEmpty:
            return identity
        case .identity(let identity):
            // The account carried no memberships; ask for the org list directly.
            let organizations = (try? await getJSON("/api/organizations"))
                .map(ClaudePlatformIdentityParser.parseOrganizations) ?? []
            ClaudePlatformDiagnostics.log(
                "no memberships in bootstrap; /api/organizations gave \(organizations.count): "
                    + organizations.map { "\(ClaudePlatformDiagnostics.shortID($0.id)) '\(ClaudePlatformDiagnostics.scrubEmails($0.name ?? "?"))' capabilities \($0.capabilities)" }
                        .joined(separator: " | ")
            )
            return ClaudePlatformIdentity(email: identity.email, organizations: organizations)
        }
    }

    // MARK: - Billing

    func fetchPrepaidCredits(organizationID: String) async throws -> ClaudePlatformPrepaidCreditsResponse {
        try await get("/api/organizations/\(organizationID)/prepaid/credits")
    }

    func fetchCurrentSpend(organizationID: String) async throws -> ClaudePlatformCurrentSpendResponse {
        try await get("/api/organizations/\(organizationID)/current_spend")
    }

    func fetchSpendLimits(organizationID: String) async throws -> ClaudePlatformSpendLimitsResponse {
        try await get("/api/organizations/\(organizationID)/spend_limits")
    }

    func fetchAutoRecharge(organizationID: String) async throws -> ClaudePlatformAutoRechargeResponse {
        try await get("/api/organizations/\(organizationID)/prepaid/auto_recharge")
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ endpoint: String) async throws -> T {
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await performRequest(request)
        try validate(response, data: data)
        do {
            return try ClaudePlatformBilling.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func getJSON(_ endpoint: String) async throws -> Any {
        let request = try makeRequest(endpoint: endpoint)
        let (data, response) = try await performRequest(request)
        try validate(response, data: data)
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func makeRequest(endpoint: String) throws -> URLRequest {
        guard !sessionCookieValues.isEmpty, let sessionCookies else {
            throw APIError.noSessionCookies
        }
        var request = URLRequest(url: baseURL.appending(path: endpoint))
        request.httpMethod = "GET"
        request.setValue(sessionCookies, forHTTPHeaderField: "Cookie")
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "PlanMonitor Claude Platform API Request"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse(
                    endpoint: request.url?.path ?? "unknown",
                    statusCode: nil,
                    bodyPreview: preview(of: data)
                )
            }
            logResponse(httpResponse, data: data, path: request.url?.path ?? "?")
            absorbSetCookies(from: httpResponse, requestURL: request.url)
            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch {
            ClaudePlatformDiagnostics.log("GET \(request.url?.path ?? "?") failed: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    /// Debug diagnostics: status, size, the *names* of any cookies the response sets and, on a
    /// failure, what answered — Cloudflare's headers say whether a challenge stood in the way.
    private func logResponse(_ response: HTTPURLResponse, data: Data, path: String) {
        ClaudePlatformDiagnostics.log({
            var line = "GET \(path) → \(response.statusCode), \(data.count) bytes"
            if let url = response.url {
                var fields: [String: String] = [:]
                for (key, value) in response.allHeaderFields {
                    if let key = key as? String, let value = value as? String { fields[key] = value }
                }
                let set = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
                if !set.isEmpty {
                    line += ", sets cookies \(ClaudePlatformDiagnostics.names(set))"
                }
            }
            if !(200...299).contains(response.statusCode) {
                let header = { (name: String) in response.value(forHTTPHeaderField: name) ?? "-" }
                line += "; server \(header("Server")), cf-ray \(header("CF-RAY")), cf-mitigated \(header("cf-mitigated"))"
                line += "; body: \(preview(of: data) ?? "(empty)")"
            }
            return line
        }())
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        default:
            throw APIError.invalidResponse(
                endpoint: response.url?.path ?? "unknown",
                statusCode: response.statusCode,
                bodyPreview: preview(of: data)
            )
        }
    }

    private func preview(of data: Data, limit: Int = 240) -> String? {
        guard !data.isEmpty, let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= limit {
            return trimmed
        }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]) + "..."
    }

    // MARK: - Cookie rotation (from `OpenAIAPIClient`)

    private func absorbSetCookies(from response: HTTPURLResponse, requestURL: URL?) {
        guard let requestURL else { return }

        var headerFields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let keyString = key as? String,
                  let valueString = value as? String else { continue }
            headerFields[keyString] = valueString
        }
        guard !headerFields.isEmpty else { return }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: requestURL)
        guard !cookies.isEmpty else { return }

        var changed = false
        for cookie in cookies {
            let isExpired = (cookie.expiresDate?.timeIntervalSinceNow ?? 1) <= 0 || cookie.value.isEmpty
            if isExpired {
                if sessionCookieValues.removeValue(forKey: cookie.name) != nil {
                    changed = true
                }
            } else if sessionCookieValues[cookie.name] != cookie.value {
                sessionCookieValues[cookie.name] = cookie.value
                changed = true
            }
        }

        guard changed else { return }
        sessionCookies = Self.serializeCookieHeader(sessionCookieValues)
    }

    static func parseCookieHeader(_ header: String) -> [String: String] {
        var cookies: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let components = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard components.count == 2 else { continue }
            let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { continue }
            cookies[name] = value
        }
        return cookies
    }

    static func serializeCookieHeader(_ cookies: [String: String]) -> String? {
        guard !cookies.isEmpty else { return nil }
        return cookies
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }
}
