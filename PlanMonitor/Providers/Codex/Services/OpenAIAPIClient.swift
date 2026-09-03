//
//  ClaudeAPIClient.swift
//  PlanTracker
//

import Foundation

actor OpenAIAPIClient {
    private let baseURL = URL(string: "https://chatgpt.com")!
    private let session: URLSession
    private var sessionCookies: String?
    private var sessionCookieValues: [String: String] = [:]
    private var accessToken: String?
    private var accessTokenFetchedAt: Date?
    private var cachedProfile: OpenAIMeProfile?
    private var cachedProfileFetchedAt: Date?

    enum APIError: Error, LocalizedError {
        case unauthorized
        case forbidden
        case networkError(Error)
        case invalidResponse(endpoint: String, statusCode: Int?, bodyPreview: String?)
        case decodingError(Error)
        case noSessionCookies
        case usageDataUnavailable

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
            case .usageDataUnavailable:
                "OpenAI usage limits are not available for this account or response format."
            }
        }
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            "Origin": "https://chatgpt.com",
            "Referer": "https://chatgpt.com/"
        ]
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func setSessionCookies(_ cookies: String) {
        sessionCookieValues = Self.parseCookieHeader(cookies)
        sessionCookies = Self.serializeCookieHeader(sessionCookieValues)
    }

    func clearSessionCookies() {
        self.sessionCookies = nil
        self.sessionCookieValues.removeAll()
        self.accessToken = nil
        self.accessTokenFetchedAt = nil
        self.cachedProfile = nil
        self.cachedProfileFetchedAt = nil
    }

    func currentSessionCookies() -> String? {
        sessionCookies
    }

    private func fetchSession() async throws -> OpenAISessionResponse {
        let request = try makeRequest(endpoint: "/api/auth/session")
        let (data, response) = try await performRequest(request)
        let sessionResponse = try decode(OpenAISessionResponse.self, from: data, response: response)

        if let token = sessionResponse.accessToken, !token.isEmpty {
            accessToken = token
            accessTokenFetchedAt = Date()
        }

        return sessionResponse
    }

    private func ensureAccessToken(forceRefresh: Bool = false, maxAge: TimeInterval = 30 * 60) async throws {
        if !forceRefresh,
           let accessToken,
           !accessToken.isEmpty,
           let accessTokenFetchedAt,
           Date().timeIntervalSince(accessTokenFetchedAt) < maxAge {
            return
        }

        _ = try await fetchSession()
    }

    func fetchMeProfile(forceRefresh: Bool = false) async throws -> OpenAIMeProfile {
        if !forceRefresh,
           let cachedProfile,
           let cachedProfileFetchedAt,
           Date().timeIntervalSince(cachedProfileFetchedAt) < 6 * 3600 {
            return cachedProfile
        }

        try await ensureAccessToken(forceRefresh: forceRefresh)
        let request = try makeRequest(endpoint: "/backend-api/me", includeAuthorization: true)
        let (data, response) = try await performRequest(request)
        let json = try decodeJSON(from: data, response: response)
        let profile = OpenAIMeParser.parseProfile(from: json)
        cachedProfile = profile
        cachedProfileFetchedAt = Date()
        return profile
    }

    /// Pay-as-you-go settings, which ChatGPT calls auto top-up. `is_enabled` is what the
    /// "Extra expenditure" header line reports; the monthly figures are present only on
    /// accounts that set a recharge budget.
    func fetchAutoTopUpSettings() async throws -> OpenAIAutoTopUpSettings {
        try await ensureAccessToken()
        let request = try makeRequest(
            endpoint: "/backend-api/subscriptions/auto_top_up/settings?include_payment_method=true",
            includeAuthorization: true
        )
        let (data, response) = try await performRequest(request)
        let json = try decodeJSON(from: data, response: response)
        guard let object = json as? [String: Any] else {
            throw APIError.usageDataUnavailable
        }
        return OpenAIAutoTopUpSettings(
            isEnabled: object["is_enabled"] as? Bool ?? false,
            monthlyLimit: (object["recharge_monthly_limit"] as? NSNumber)?.doubleValue,
            monthlyRemaining: (object["recharge_monthly_remaining"] as? NSNumber)?.doubleValue
        )
    }

    func fetchUsageSnapshot(includeMetadataEndpoints: Bool = false) async throws -> OpenAIUsageSnapshot {
        try await ensureAccessToken()
        return try await fetchUsageSnapshotInternal(includeMetadataEndpoints: includeMetadataEndpoints)
    }

    private func fetchUsageSnapshotInternal(includeMetadataEndpoints: Bool) async throws -> OpenAIUsageSnapshot {
        var snapshots: [OpenAIUsageSnapshot] = []
        var lastError: Error?

        for candidate in usageEndpoints(includeMetadataEndpoints: includeMetadataEndpoints) {
            do {
                let request = try makeRequest(
                    endpoint: candidate.endpoint,
                    method: candidate.method,
                    body: candidate.body,
                    includeAuthorization: candidate.requiresAuth
                )
                let (data, response) = try await performRequest(request)
                let json = try decodeJSON(from: data, response: response)
                let snapshot = OpenAIUsageParser.parseSnapshot(
                    from: json,
                    collectLimits: candidate.collectLimits
                )
                snapshots.append(snapshot)
            } catch {
                lastError = error
            }
        }

        let merged = mergeSnapshots(snapshots)
        if !merged.limits.isEmpty || merged.planLabel != nil {
            return merged
        }

        if !includeMetadataEndpoints {
            return try await fetchUsageSnapshotInternal(includeMetadataEndpoints: true)
        }

        if let lastError {
            throw lastError
        }
        throw APIError.usageDataUnavailable
    }

    private func usageEndpoints(includeMetadataEndpoints: Bool) -> [UsageEndpointCandidate] {
        var endpoints = [
            UsageEndpointCandidate(
                endpoint: "/backend-api/wham/usage",
                method: "GET",
                body: nil,
                requiresAuth: true,
                collectLimits: true
            )
        ]

        if includeMetadataEndpoints {
            endpoints.append(contentsOf: [
                UsageEndpointCandidate(
                    endpoint: "/backend-api/wham/usage/daily-token-usage-breakdown",
                    method: "GET",
                    body: nil,
                    requiresAuth: true,
                    collectLimits: false
                ),
                UsageEndpointCandidate(
                    endpoint: "/backend-api/wham/usage/credit-usage-events",
                    method: "GET",
                    body: nil,
                    requiresAuth: true,
                    collectLimits: false
                ),
                UsageEndpointCandidate(
                    endpoint: "/backend-api/checkout_pricing_config/configs/\(currentRegionIdentifier())",
                    method: "GET",
                    body: nil,
                    requiresAuth: true,
                    collectLimits: false
                ),
                UsageEndpointCandidate(
                    endpoint: "/backend-api/checkout_pricing_config/configs/ES",
                    method: "GET",
                    body: nil,
                    requiresAuth: true,
                    collectLimits: false
                ),
                UsageEndpointCandidate(
                    endpoint: "/backend-api/subscriptions",
                    method: "GET",
                    body: nil,
                    requiresAuth: true,
                    collectLimits: false
                )
            ])
        }

        return endpoints
    }

    private func currentRegionIdentifier() -> String {
        Locale.current.region?.identifier ?? "US"
    }

    private func mergeSnapshots(_ snapshots: [OpenAIUsageSnapshot]) -> OpenAIUsageSnapshot {
        let planLabel = snapshots.compactMap(\.planLabel).first
        var seen = Set<OpenAIUsageLimit>()
        var mergedLimits: [OpenAIUsageLimit] = []

        for snapshot in snapshots {
            for limit in snapshot.limits where seen.insert(limit).inserted {
                mergedLimits.append(limit)
            }
        }

        let billing = snapshots.map(\.billing).first { !$0.isEmpty } ?? .empty
        return OpenAIUsageSnapshot(planLabel: planLabel, limits: mergedLimits, billing: billing)
    }

    private struct UsageEndpointCandidate {
        let endpoint: String
        let method: String
        let body: Data?
        let requiresAuth: Bool
        let collectLimits: Bool
    }

    private func makeRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        includeAuthorization: Bool = false
    ) throws -> URLRequest {
        if sessionCookieValues.isEmpty, let sessionCookies {
            sessionCookieValues = Self.parseCookieHeader(sessionCookies)
            self.sessionCookies = Self.serializeCookieHeader(sessionCookieValues)
        }

        guard !sessionCookieValues.isEmpty, let sessionCookies else {
            throw APIError.noSessionCookies
        }

        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            throw APIError.invalidResponse(
                endpoint: endpoint,
                statusCode: nil,
                bodyPreview: nil
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(sessionCookies, forHTTPHeaderField: "Cookie")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if includeAuthorization, let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "PlanMonitor OpenAI API Request"
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
            absorbSetCookies(from: httpResponse, requestURL: request.url)
            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T {
        switch response.statusCode {
        case 200 ... 299:
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(type, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        default:
            let endpoint = response.url?.path ?? "unknown"
            let preview = preview(of: data)
            throw APIError.invalidResponse(
                endpoint: endpoint,
                statusCode: response.statusCode,
                bodyPreview: preview
            )
        }
    }

    private func decodeJSON(from data: Data, response: HTTPURLResponse) throws -> Any {
        switch response.statusCode {
        case 200 ... 299:
            do {
                return try JSONSerialization.jsonObject(with: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        default:
            let endpoint = response.url?.path ?? "unknown"
            let preview = preview(of: data)
            throw APIError.invalidResponse(
                endpoint: endpoint,
                statusCode: response.statusCode,
                bodyPreview: preview
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

    private static func parseCookieHeader(_ header: String) -> [String: String] {
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

    private static func serializeCookieHeader(_ cookies: [String: String]) -> String? {
        guard !cookies.isEmpty else { return nil }
        return cookies
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }
}

// MARK: - Response Models

nonisolated struct OpenAISessionResponse: Codable, Sendable {
    let accessToken: String?
    let user: User?

    struct User: Codable, Sendable {
        let email: String?
        let name: String?
    }
}

/// ChatGPT's auto top-up settings. Amounts are account currency units (dollars), which the
/// domain model stores as integer minor units.
nonisolated struct OpenAIAutoTopUpSettings: Sendable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let monthlyRemaining: Double?
}

nonisolated struct OpenAIUsageSnapshot: Sendable {
    let planLabel: String?
    let limits: [OpenAIUsageLimit]
    /// Money-side fields the usage endpoint reports alongside the windows.
    var billing: OpenAIBillingSnapshot = .empty
}

/// `credits` and `spend_control` from the usage payload. Amounts are account currency units
/// (dollars); the domain model stores integer minor units.
nonisolated struct OpenAIBillingSnapshot: Sendable {
    var creditBalance: Double?
    var hasCredits: Bool?
    var overageLimitReached: Bool?
    var spendLimit: Double?
    var spendLimitReached: Bool?

    static let empty = OpenAIBillingSnapshot()

    var isEmpty: Bool {
        creditBalance == nil && hasCredits == nil && overageLimitReached == nil
            && spendLimit == nil && spendLimitReached == nil
    }

    /// A JSON number, or a decimal string as `credits.balance` uses.
    static func amount(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    static func parse(_ json: Any) -> OpenAIBillingSnapshot {
        guard let object = json as? [String: Any] else { return .empty }
        var snapshot = OpenAIBillingSnapshot()
        if let credits = object["credits"] as? [String: Any] {
            snapshot.creditBalance = amount(credits["balance"])
            snapshot.hasCredits = credits["has_credits"] as? Bool
            snapshot.overageLimitReached = credits["overage_limit_reached"] as? Bool
        }
        if let spend = object["spend_control"] as? [String: Any] {
            snapshot.spendLimit = amount(spend["individual_limit"])
            snapshot.spendLimitReached = spend["reached"] as? Bool
        }
        return snapshot
    }
}

nonisolated struct OpenAIUsageLimit: Sendable, Hashable {
    let name: String
    let utilization: Double
    let resetsAt: Date?
}

nonisolated private enum OpenAIUsageParser {
    static func parseSnapshot(from json: Any, collectLimits: Bool) -> OpenAIUsageSnapshot {
        var collector = Collector(collectLimits: collectLimits)
        collector.walk(json, path: [])
        return OpenAIUsageSnapshot(
            planLabel: collector.planLabel,
            limits: collector.normalizedLimits(),
            billing: OpenAIBillingSnapshot.parse(json)
        )
    }

    private struct Collector {
        let collectLimits: Bool
        var planLabel: String?
        private var limits: [CandidateLimit] = []

        init(collectLimits: Bool) {
            self.collectLimits = collectLimits
            self.planLabel = nil
            self.limits = []
        }

        mutating func walk(_ value: Any, path: [String]) {
            if let dict = value as? [String: Any] {
                inspect(dictionary: dict, path: path)
                for (key, nested) in dict {
                    walk(nested, path: path + [key])
                }
                return
            }

            if let array = value as? [Any] {
                for (index, nested) in array.enumerated() {
                    walk(nested, path: path + ["[\(index)]"])
                }
            }
        }

        mutating func inspect(dictionary: [String: Any], path: [String]) {
            if planLabel == nil {
                planLabel = detectPlan(in: dictionary)
            }

            if collectLimits, let candidate = candidateLimit(from: dictionary, path: path) {
                limits.append(candidate)
            }
        }

        private func detectPlan(in dictionary: [String: Any]) -> String? {
            let stringValues = dictionary.compactMap { key, value -> String? in
                guard let string = value as? String else { return nil }
                let normalizedKey = key.lowercased()
                if normalizedKey.contains("plan") || normalizedKey.contains("tier") || normalizedKey.contains("subscription") {
                    return string
                }
                return nil
            }

            let knownPlans = ["free", "plus", "pro", "team", "enterprise", "business"]
            for value in stringValues {
                let lowercased = value.lowercased()
                if knownPlans.contains(where: { lowercased.contains($0) }) {
                    return value
                }
            }
            return nil
        }

        private func candidateLimit(from dictionary: [String: Any], path: [String]) -> CandidateLimit? {
            guard isLikelyUsageDictionary(dictionary, path: path) else { return nil }

            let percentKeys = ["utilization", "percent_used", "used_percent", "usage_percent", "usagePct"]
            var utilization = percentKeys.compactMap { OpenAIUsageParser.number(from: dictionary[$0]) }.first

            if utilization == nil {
                let numericTriples: [(used: [String], remaining: [String], limit: [String])] = [
                    (["used", "consumed"], ["remaining"], ["limit", "max", "quota", "total"]),
                    (["current"], ["remaining"], ["max"])
                ]

                for triple in numericTriples {
                    let usedValue = firstNumber(in: dictionary, keys: triple.used)
                    let remainingValue = firstNumber(in: dictionary, keys: triple.remaining)
                    let limitValue = firstNumber(in: dictionary, keys: triple.limit)

                    if let usedValue, let limitValue, limitValue > 0 {
                        utilization = (usedValue / limitValue) * 100
                        break
                    }

                    if let remainingValue, let limitValue, limitValue > 0 {
                        utilization = ((limitValue - remainingValue) / limitValue) * 100
                        break
                    }
                }
            }

            guard let rawUtilization = utilization else { return nil }
            let clampedUtilization = max(0, min(100, rawUtilization))

            let resetDate = extractResetDate(from: dictionary)
            let name = extractName(from: dictionary, path: path)

            return CandidateLimit(name: name, utilization: clampedUtilization, resetsAt: resetDate)
        }

        private func isLikelyUsageDictionary(_ dictionary: [String: Any], path: [String]) -> Bool {
            let normalizedKeys = dictionary.keys.map { $0.lowercased() }
            let pathString = path.joined(separator: "/").lowercased()

            let hasPercentKey = normalizedKeys.contains { key in
                ["utilization", "percent_used", "used_percent", "usage_percent", "usagepct"].contains(key)
            }
            let hasUsedKey = normalizedKeys.contains { key in
                ["used", "consumed", "current"].contains(key)
            }
            let hasLimitKey = normalizedKeys.contains { key in
                ["limit", "max", "quota", "total"].contains(key)
            }
            let hasRemainingKey = normalizedKeys.contains { key in
                ["remaining", "left"].contains(key)
            }
            let hasResetKey = normalizedKeys.contains { key in
                key.contains("reset") || key.contains("expires")
            }
            let hasNameKey = normalizedKeys.contains { key in
                ["label", "name", "title", "slug", "model", "model_slug"].contains(key)
            }
            let hasUsageContext = pathString.contains("usage")
                || pathString.contains("limit")
                || pathString.contains("quota")
                || pathString.contains("window")
                || pathString.contains("token")
                || pathString.contains("credit")

            let hasUtilizationShape = hasPercentKey || ((hasUsedKey || hasRemainingKey) && hasLimitKey)

            // Keep parser away from pricing config objects that carry numbers but are not usage counters.
            let looksLikePricing = normalizedKeys.contains(where: { key in
                key.contains("price") || key.contains("amount") || key.contains("currency_symbol")
            })

            if looksLikePricing && !hasUtilizationShape {
                return false
            }

            if hasUtilizationShape && (hasUsageContext || hasResetKey || hasNameKey) {
                return true
            }

            return false
        }

        private func firstNumber(in dictionary: [String: Any], keys: [String]) -> Double? {
            for key in keys {
                if let value = OpenAIUsageParser.number(from: dictionary[key]) {
                    return value
                }
            }
            return nil
        }

        private func extractName(from dictionary: [String: Any], path: [String]) -> String {
            let preferredKeys = ["label", "name", "title", "slug", "model", "model_slug", "plan"]
            for key in preferredKeys {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }

            let meaningful = path.reversed().first { segment in
                !segment.hasPrefix("[")
            }
            return meaningful ?? "usage"
        }

        private func extractResetDate(from dictionary: [String: Any]) -> Date? {
            for (key, value) in dictionary {
                let lowercased = key.lowercased()
                guard lowercased.contains("reset") || lowercased.contains("expires") || lowercased.contains("window") else {
                    continue
                }

                if let date = OpenAIUsageParser.parseDate(value) {
                    return date
                }
            }
            return nil
        }

        func normalizedLimits() -> [OpenAIUsageLimit] {
            var seen = Set<String>()
            var normalized: [OpenAIUsageLimit] = []

            for limit in limits {
                let bucketedUtilization = Int(limit.utilization.rounded())
                let resetBucket = limit.resetsAt.map { Int($0.timeIntervalSince1970 / 60) } ?? -1
                let key = "\(limit.name.lowercased())|\(bucketedUtilization)|\(resetBucket)"
                guard seen.insert(key).inserted else { continue }

                normalized.append(
                    OpenAIUsageLimit(
                        name: limit.name,
                        utilization: limit.utilization,
                        resetsAt: limit.resetsAt
                    )
                )
            }

            return normalized.sorted { lhs, rhs in
                switch (lhs.resetsAt, rhs.resetsAt) {
                case let (l?, r?): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.name < rhs.name
                }
            }
        }

        private struct CandidateLimit {
            let name: String
            let utilization: Double
            let resetsAt: Date?
        }
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func parseDate(_ value: Any) -> Date? {
        if let number = number(from: value) {
            if number > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000)
            }
            if number > 1_000_000_000 {
                return Date(timeIntervalSince1970: number)
            }
        }

        guard let string = value as? String, !string.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)
    }
}

nonisolated struct OpenAIMeProfile: Sendable {
    let email: String?
    let planLabel: String?
    let displayName: String?
}

nonisolated private enum OpenAIMeParser {
    static func parseProfile(from json: Any) -> OpenAIMeProfile {
        let email = findString(in: json, matching: ["email"])
        let displayName = findString(in: json, matching: ["name", "display_name"])
        let plan = findString(in: json, matching: ["plan", "plan_type", "tier", "subscription_plan"])

        return OpenAIMeProfile(email: email, planLabel: plan, displayName: displayName)
    }

    private static func findString(in value: Any, matching keys: [String]) -> String? {
        if let dict = value as? [String: Any] {
            for (key, nested) in dict {
                let normalized = key.lowercased()
                if keys.contains(normalized), let string = nested as? String, !string.isEmpty {
                    return string
                }
            }

            for nested in dict.values {
                if let result = findString(in: nested, matching: keys) {
                    return result
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let result = findString(in: nested, matching: keys) {
                    return result
                }
            }
        }

        return nil
    }
}
