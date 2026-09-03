//
//  ClaudeAPIClient.swift
//  PlanTracker
//

import Foundation

actor ClaudeAPIClient {
    private let baseURL = URL(string: "https://claude.ai")!
    private let session: URLSession
    private var sessionKey: String?

    enum APIError: Error, LocalizedError {
        case unauthorized
        case forbidden
        case networkError(Error)
        case invalidResponse(endpoint: String, statusCode: Int?, bodyPreview: String?)
        case decodingError(Error)
        case noSessionKey

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Session expired. Please log in again."
            case .forbidden:
                "Access denied. Please log in again."
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
            case .noSessionKey:
                "Not authenticated. Please log in."
            }
        }
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
        ]
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func setSessionKey(_ key: String) {
        self.sessionKey = key
    }

    func clearSessionKey() {
        self.sessionKey = nil
    }

    private func makeRequest(endpoint: String) throws -> URLRequest {
        guard let sessionKey else {
            throw APIError.noSessionKey
        }

        let url = baseURL.appending(path: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let cookieValue = sessionKey.contains("=") ? sessionKey : "sessionKey=\(sessionKey)"
        request.setValue(cookieValue, forHTTPHeaderField: "Cookie")

        return request
    }

    func fetchBootstrap() async throws -> BootstrapResponse {
        let request = try makeRequest(endpoint: "/api/bootstrap")
        let (data, response) = try await performRequest(request)
        return try decode(BootstrapResponse.self, from: data, response: response)
    }

    func fetchOrganizations() async throws -> [Organization] {
        let request = try makeRequest(endpoint: "/api/organizations")
        let (data, response) = try await performRequest(request)
        return try decode([Organization].self, from: data, response: response)
    }

    /// Fetch usage data for an organization
    func fetchUsage(orgUuid: String) async throws -> UsageResponse {
        let request = try makeRequest(endpoint: "/api/organizations/\(orgUuid)/usage")
        let (data, response) = try await performRequest(request)

        do {
            return try decode(UsageResponse.self, from: data, response: response)
        } catch let APIError.decodingError(decodingError) {
            let json = try decodeJSON(from: data, response: response)
            if let parsed = UsageResponseParser.parse(from: json) {
                return parsed
            }
            throw APIError.decodingError(decodingError)
        }
    }

    /// Fetch prepaid credits balance
    func fetchPrepaidCredits(orgUuid: String) async throws -> PrepaidCreditsResponse? {
        let request = try makeRequest(endpoint: "/api/organizations/\(orgUuid)/prepaid/credits")
        do {
            let (data, response) = try await performRequest(request)
            return try decode(PrepaidCreditsResponse.self, from: data, response: response)
        } catch {
            return nil
        }
    }

    /// Fetch monthly overage spend limit
    func fetchOverageSpendLimit(orgUuid: String) async throws -> OverageSpendLimitResponse? {
        let request = try makeRequest(endpoint: "/api/organizations/\(orgUuid)/overage_spend_limit")
        do {
            let (data, response) = try await performRequest(request)
            return try decode(OverageSpendLimitResponse.self, from: data, response: response)
        } catch {
            return nil
        }
    }

    /// Fetch overage credit grant info
    func fetchOverageCreditGrant(orgUuid: String) async throws -> OverageCreditGrantResponse? {
        let request = try makeRequest(endpoint: "/api/organizations/\(orgUuid)/overage_credit_grant")
        do {
            let (data, response) = try await performRequest(request)
            return try decode(OverageCreditGrantResponse.self, from: data, response: response)
        } catch {
            return nil
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "PlanMonitor Claude API Request"
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
            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T {
        switch response.statusCode {
        case 200...299:
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
        case 200...299:
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
}

// MARK: - Response Models

nonisolated struct BootstrapResponse: Codable, Sendable {
    let account: Account?

    struct Account: Codable, Sendable {
        let uuid: String?
        let emailAddress: String?
        let displayName: String?
    }
}

nonisolated struct Organization: Codable, Sendable {
    let uuid: String?
    let name: String?
    let rateLimitTier: String?
    let capabilities: [String]?
    let activeFlags: [String]?
    let settings: OrgSettings?

    struct OrgSettings: Codable, Sendable {
        let claudeConsolePrivacy: String?
    }
}

nonisolated struct UsageResponse: Decodable, Sendable {
    let fiveHour: UsagePeriod?
    let sevenDay: UsagePeriod?
    let sevenDayOpus: UsagePeriod?
    let sevenDaySonnet: UsagePeriod?
    let sevenDayScoped: ScopedUsagePeriod?
    let sevenDayOauthApps: UsagePeriod?
    let sevenDayCowork: UsagePeriod?
    let iguanaNecktie: UsagePeriod?
    let extraUsage: UsagePeriod?
    let extraUsageEnabled: Bool?
    let spend: Spend?

    private enum CodingKeys: String, CodingKey {
        case fiveHour
        case sevenDay
        case sevenDayOpus
        case sevenDaySonnet
        case sevenDayOauthApps
        case sevenDayCowork
        case iguanaNecktie
        case extraUsage
        case spend
        case limits
    }

    init(
        fiveHour: UsagePeriod?,
        sevenDay: UsagePeriod?,
        sevenDayOpus: UsagePeriod?,
        sevenDaySonnet: UsagePeriod?,
        sevenDayScoped: ScopedUsagePeriod? = nil,
        sevenDayOauthApps: UsagePeriod?,
        sevenDayCowork: UsagePeriod?,
        iguanaNecktie: UsagePeriod?,
        extraUsage: UsagePeriod?,
        extraUsageEnabled: Bool? = nil,
        spend: Spend? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayScoped = sevenDayScoped
        self.sevenDayOauthApps = sevenDayOauthApps
        self.sevenDayCowork = sevenDayCowork
        self.iguanaNecktie = iguanaNecktie
        self.extraUsage = extraUsage
        self.extraUsageEnabled = extraUsageEnabled
        self.spend = spend
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limits = try container.decodeIfPresent([UsageLimit].self, forKey: .limits) ?? []

        fiveHour = try container.decodeIfPresent(UsagePeriod.self, forKey: .fiveHour)
            ?? Self.bestLimit(in: limits, matching: { $0.normalizedKind == "session" || $0.normalizedGroup == "session" })?.period
        sevenDay = try container.decodeIfPresent(UsagePeriod.self, forKey: .sevenDay)
            ?? Self.bestLimit(in: limits, matching: { $0.normalizedKind == "weekly_all" })?.period
            ?? Self.bestLimit(in: limits, matching: { $0.normalizedGroup == "weekly" && $0.modelDisplayName == nil })?.period
        sevenDayOpus = try container.decodeIfPresent(UsagePeriod.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try container.decodeIfPresent(UsagePeriod.self, forKey: .sevenDaySonnet)
        sevenDayScoped = Self.bestWeeklyScopedLimit(in: limits)
        sevenDayOauthApps = try container.decodeIfPresent(UsagePeriod.self, forKey: .sevenDayOauthApps)
        sevenDayCowork = try container.decodeIfPresent(UsagePeriod.self, forKey: .sevenDayCowork)
        iguanaNecktie = try container.decodeIfPresent(UsagePeriod.self, forKey: .iguanaNecktie)
        extraUsage = try? container.decodeIfPresent(UsagePeriod.self, forKey: .extraUsage)
        extraUsageEnabled = try container.decodeIfPresent(ExtraUsageMetadata.self, forKey: .extraUsage)?.isEnabled
        spend = try container.decodeIfPresent(Spend.self, forKey: .spend)
    }

    private static func bestWeeklyScopedLimit(in limits: [UsageLimit]) -> ScopedUsagePeriod? {
        guard let limit = bestLimit(
            in: limits,
            matching: {
                ($0.normalizedKind == "weekly_scoped" || $0.normalizedGroup == "weekly")
                    && $0.modelDisplayName != nil
            }
        ),
              let label = limit.modelDisplayName,
              let period = limit.period else {
            return nil
        }

        return ScopedUsagePeriod(label: label, period: period)
    }

    private static func bestLimit(
        in limits: [UsageLimit],
        matching predicate: (UsageLimit) -> Bool
    ) -> UsageLimit? {
        limits
            .filter { predicate($0) && $0.period != nil }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive == true
                }
                return lhs.percent > rhs.percent
            }
            .first
    }

    struct ScopedUsagePeriod: Sendable {
        let label: String
        let period: UsagePeriod
    }

    struct Spend: Decodable, Sendable {
        let used: MoneyAmount?
        let limit: MoneyAmount?
        let percent: Double?
        let enabled: Bool?
        let balance: MoneyAmount?
        let cap: Cap?

        struct Cap: Decodable, Sendable {
            let credits: MoneyAmount?
        }
    }

    struct ExtraUsageMetadata: Decodable, Sendable {
        let isEnabled: Bool?
    }

    struct MoneyAmount: Decodable, Sendable {
        let amountMinor: Int?
        let currency: String?
        let exponent: Int?

        private enum CodingKeys: String, CodingKey {
            case amountMinor
            case amount_minor
            case currency
            case exponent
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            amountMinor = try Self.decodeFlexibleIntIfPresent(in: container, forKey: .amountMinor)
                ?? Self.decodeFlexibleIntIfPresent(in: container, forKey: .amount_minor)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
            exponent = try Self.decodeFlexibleIntIfPresent(in: container, forKey: .exponent)
        }

        private static func decodeFlexibleIntIfPresent(
            in container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Int? {
            if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try container.decodeIfPresent(Double.self, forKey: key) {
                return Int(value.rounded())
            }
            if let value = try container.decodeIfPresent(String.self, forKey: key) {
                return Double(value).map { Int($0.rounded()) }
            }
            return nil
        }
    }

    struct UsagePeriod: Decodable, Sendable {
        let utilization: Double
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case percent
            case resetsAt
            case resets_at
            case usedCredits
            case used_credits
            case monthlyLimit
            case monthly_limit
            case remaining
            case left
            case limit
            case max
            case quota
            case total
        }

        init(utilization: Double, resetsAt: String?) {
            self.utilization = utilization
            self.resetsAt = resetsAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let rawUtilization =
                try Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .utilization) ??
                Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .percent)

            let used =
                try Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .usedCredits) ??
                Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .used_credits)

            let limit =
                try Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .monthlyLimit) ??
                Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .monthly_limit) ??
                Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .limit) ??
                Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .max) ??
                Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .quota) ??
                Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .total)

            let remaining =
                try Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .remaining) ??
                Self.decodeFlexibleDoubleIfPresent(in: container, forKey: .left)

            let derivedUtilization: Double?
            if let rawUtilization {
                derivedUtilization = rawUtilization
            } else if let used, let limit, limit > 0 {
                derivedUtilization = (used / limit) * 100.0
            } else if let remaining, let limit, limit > 0 {
                derivedUtilization = ((limit - remaining) / limit) * 100.0
            } else {
                derivedUtilization = nil
            }

            guard let derivedUtilization else {
                throw DecodingError.dataCorruptedError(
                    forKey: .utilization,
                    in: container,
                    debugDescription: "Usage period is missing utilization and no derivation keys were found"
                )
            }

            utilization = max(0, min(100, derivedUtilization))
            resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
                ?? container.decodeIfPresent(String.self, forKey: .resets_at)
        }

        private static func decodeFlexibleDoubleIfPresent(
            in container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Double? {
            if let value = try container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }
            if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                return Double(value)
            }
            if let value = try container.decodeIfPresent(String.self, forKey: key) {
                return Double(value)
            }
            return nil
        }
    }

    private struct UsageLimit: Decodable {
        let kind: String?
        let group: String?
        let percent: Double
        let resetsAt: String?
        private let scope: Scope?
        let isActive: Bool?

        var normalizedKind: String {
            Self.normalize(kind)
        }

        var normalizedGroup: String {
            Self.normalize(group)
        }

        var modelDisplayName: String? {
            guard let displayName = scope?.model?.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty else {
                return nil
            }
            return displayName
        }

        var period: UsagePeriod? {
            UsagePeriod(utilization: percent, resetsAt: resetsAt)
        }

        private static func normalize(_ value: String?) -> String {
            value?
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: "_") ?? ""
        }

        private struct Scope: Decodable {
            let model: Model?
        }

        private struct Model: Decodable {
            let displayName: String?
        }
    }
}

private nonisolated enum UsageResponseParser {
    static func parse(from json: Any) -> UsageResponse? {
        var collector = Collector()
        collector.walk(json, path: [])
        return collector.build()
    }

    private struct Collector {
        private var candidates: [CandidatePeriod] = []
        private var extraUsageEnabled: Bool?

        mutating func walk(_ value: Any, path: [String]) {
            if let dictionary = value as? [String: Any] {
                inspect(dictionary: dictionary, path: path)
                for (key, nested) in dictionary {
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
            if extraUsageEnabled == nil,
               path.contains(where: { normalize($0) == "extra_usage" || normalize($0) == "extrausage" }) {
                extraUsageEnabled = firstBool(in: dictionary, keys: ["is_enabled", "isEnabled", "enabled"])
            }

            if let direct = directPeriods(from: dictionary) {
                candidates.append(contentsOf: direct)
            }

            if let candidate = candidatePeriod(from: dictionary, path: path) {
                candidates.append(candidate)
            }
        }

        func build() -> UsageResponse? {
            let normalized = deduplicatedCandidates()
            guard !normalized.isEmpty else { return nil }

            var remaining = normalized

            let fiveHour = popBest(from: &remaining, minimumScore: 1, scoring: fiveHourScore)
            let sevenDay = popBest(from: &remaining, minimumScore: 1, scoring: sevenDayScore)
            let sevenDayOpus = popBest(from: &remaining, minimumScore: 1, scoring: opusScore)
            let sevenDaySonnet = popBest(from: &remaining, minimumScore: 1, scoring: sonnetScore)
            let sevenDayScoped = popBest(from: &remaining, minimumScore: 1, scoring: scopedWeeklyScore)
            let sevenDayOauthApps = popBest(from: &remaining, minimumScore: 1, scoring: oauthAppsScore)
            let sevenDayCowork = popBest(from: &remaining, minimumScore: 1, scoring: coworkScore)
            let iguanaNecktie = popBest(from: &remaining, minimumScore: 1, scoring: iguanaScore)
            let extraUsage = popBest(from: &remaining, minimumScore: 1, scoring: extraUsageScore)

            return UsageResponse(
                fiveHour: fiveHour?.period,
                sevenDay: sevenDay?.period,
                sevenDayOpus: sevenDayOpus?.period,
                sevenDaySonnet: sevenDaySonnet?.period,
                sevenDayScoped: sevenDayScoped.map {
                    UsageResponse.ScopedUsagePeriod(label: $0.displayName, period: $0.period)
                },
                sevenDayOauthApps: sevenDayOauthApps?.period,
                sevenDayCowork: sevenDayCowork?.period,
                iguanaNecktie: iguanaNecktie?.period,
                extraUsage: extraUsage?.period,
                extraUsageEnabled: extraUsageEnabled
            )
        }

        private func directPeriods(from dictionary: [String: Any]) -> [CandidatePeriod]? {
            let mappings: [(String, [String])] = [
                ("five_hour", ["five_hour", "fivehour", "five_hour_limit"]),
                ("seven_day", ["seven_day", "sevenday", "weekly", "weekly_limit"]),
                ("seven_day_opus", ["seven_day_opus", "sevendayopus", "opus"]),
                ("seven_day_sonnet", ["seven_day_sonnet", "sevendaysonnet", "sonnet"]),
                ("weekly_scoped", ["weekly_scoped", "seven_day_scoped", "sevendayscoped", "fable"]),
                ("seven_day_oauth_apps", ["seven_day_oauth_apps", "oauth_apps", "oauthapps"]),
                ("seven_day_cowork", ["seven_day_cowork", "cowork"]),
                ("iguana_necktie", ["iguana_necktie", "iguananecktie"]),
                ("extra_usage", ["extra_usage", "extrausage"])
            ]

            var results: [CandidatePeriod] = []

            for (canonicalName, aliases) in mappings {
                for (key, value) in dictionary {
                    let normalizedKey = normalize(key)
                    guard aliases.contains(normalizedKey),
                          let period = period(from: value) else { continue }
                    results.append(
                        CandidatePeriod(
                            name: canonicalName,
                            path: [key],
                            period: period
                        )
                    )
                }
            }

            return results.isEmpty ? nil : results
        }

        private func candidatePeriod(from dictionary: [String: Any], path: [String]) -> CandidatePeriod? {
            guard let period = period(from: dictionary) else { return nil }
            return CandidatePeriod(
                name: candidateName(from: dictionary, path: path),
                path: path,
                period: period
            )
        }

        private func period(from value: Any) -> UsageResponse.UsagePeriod? {
            guard let dictionary = value as? [String: Any] else { return nil }

            let utilization = firstNumber(
                in: dictionary,
                keys: ["utilization", "percent", "percentage", "percent_used", "used_percent", "usage_percent"]
            ) ?? derivedUtilization(from: dictionary)

            guard let utilization else { return nil }

            let reset = firstString(
                in: dictionary,
                keys: ["resets_at", "reset_at", "resetsAt", "resetAt", "expires_at", "expiresAt"]
            )

            return UsageResponse.UsagePeriod(
                utilization: max(0, min(100, utilization)),
                resetsAt: reset
            )
        }

        private func derivedUtilization(from dictionary: [String: Any]) -> Double? {
            let used = firstNumber(in: dictionary, keys: ["used", "consumed", "current"])
            let remaining = firstNumber(in: dictionary, keys: ["remaining", "left"])
            let limit = firstNumber(in: dictionary, keys: ["limit", "max", "quota", "total"])

            if let used, let limit, limit > 0 {
                return (used / limit) * 100
            }

            if let remaining, let limit, limit > 0 {
                return ((limit - remaining) / limit) * 100
            }

            return nil
        }

        private func candidateName(from dictionary: [String: Any], path: [String]) -> String {
            if isScopedWeekly(dictionary),
               let displayName = modelDisplayName(from: dictionary) {
                return displayName
            }

            for key in ["name", "label", "title", "slug", "model", "kind", "type"] {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }
            if let displayName = modelDisplayName(from: dictionary) {
                return displayName
            }

            return path.last(where: { !$0.hasPrefix("[") }) ?? "usage"
        }

        private func isScopedWeekly(_ dictionary: [String: Any]) -> Bool {
            let kind = (dictionary["kind"] as? String).map(normalize) ?? ""
            let group = (dictionary["group"] as? String).map(normalize) ?? ""
            return kind == "weekly_scoped" || group == "weekly"
        }

        private func modelDisplayName(from dictionary: [String: Any]) -> String? {
            guard let scope = dictionary["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let displayName = model["display_name"] as? String,
                  !displayName.isEmpty else {
                return nil
            }
            return displayName
        }

        private func deduplicatedCandidates() -> [CandidatePeriod] {
            var seen = Set<String>()
            var result: [CandidatePeriod] = []

            for candidate in candidates {
                let bucket = Int(candidate.period.utilization.rounded())
                let reset = candidate.period.resetsAt ?? "nil"
                let key = "\(normalize(candidate.name))|\(bucket)|\(reset)"
                guard seen.insert(key).inserted else { continue }
                result.append(candidate)
            }

            return result
        }

        private func firstNumber(in dictionary: [String: Any], keys: [String]) -> Double? {
            for key in keys {
                if let number = UsageResponseParser.number(from: dictionary[key]) {
                    return number
                }
            }
            return nil
        }

        private func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
            for key in keys {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        private func firstBool(in dictionary: [String: Any], keys: [String]) -> Bool? {
            for key in keys {
                if let value = dictionary[key] as? Bool {
                    return value
                }
                if let number = dictionary[key] as? NSNumber {
                    return number.boolValue
                }
                if let string = dictionary[key] as? String {
                    switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "true", "yes", "1":
                        return true
                    case "false", "no", "0":
                        return false
                    default:
                        continue
                    }
                }
            }
            return nil
        }

        private func popBest(
            from candidates: inout [CandidatePeriod],
            minimumScore: Int,
            scoring: (CandidatePeriod) -> Int
        ) -> CandidatePeriod? {
            var bestIndex: Int?
            var bestScore = Int.min

            for (index, candidate) in candidates.enumerated() {
                let score = scoring(candidate)
                guard score >= minimumScore else { continue }

                if let currentBestIndex = bestIndex {
                    let currentBest = candidates[currentBestIndex]
                    if score > bestScore || (score == bestScore && compareOrder(candidate, currentBest)) {
                        bestIndex = index
                        bestScore = score
                    }
                } else {
                    bestIndex = index
                    bestScore = score
                }
            }

            guard let bestIndex else { return nil }
            return candidates.remove(at: bestIndex)
        }

        private func fiveHourScore(_ candidate: CandidatePeriod) -> Int {
            var score = 0
            let name = normalizedName(candidate)
            if containsAny(name, ["five_hour", "fivehour", "5h", "hourly"]) { score += 220 }
            if containsAny(name, ["hour"]) { score += 90 }
            if containsAny(name, ["day", "week", "weekly"]) { score -= 80 }
            if let hours = hoursUntilReset(candidate), hours > 0, hours <= 12 { score += 100 }
            return score
        }

        private func sevenDayScore(_ candidate: CandidatePeriod) -> Int {
            var score = 0
            let name = normalizedName(candidate)
            if containsAny(name, ["seven_day", "sevenday", "weekly", "week"]) { score += 220 }
            if containsAny(name, ["hour", "five_hour", "5h"]) { score -= 80 }
            if let hours = hoursUntilReset(candidate), hours >= 24, hours <= 240 { score += 100 }
            return score
        }

        private func opusScore(_ candidate: CandidatePeriod) -> Int {
            let name = normalizedName(candidate)
            return containsAny(name, ["opus"]) ? 260 : 0
        }

        private func sonnetScore(_ candidate: CandidatePeriod) -> Int {
            let name = normalizedName(candidate)
            return containsAny(name, ["sonnet"]) ? 260 : 0
        }

        private func scopedWeeklyScore(_ candidate: CandidatePeriod) -> Int {
            let name = normalizedName(candidate)
            guard containsAny(name, ["weekly_scoped", "seven_day_scoped", "fable"]) else {
                return 0
            }
            if containsAny(name, ["opus", "sonnet", "oauth", "cowork"]) {
                return 0
            }
            return 240
        }

        private func oauthAppsScore(_ candidate: CandidatePeriod) -> Int {
            let name = normalizedName(candidate)
            return containsAny(name, ["oauth", "apps"]) ? 220 : 0
        }

        private func coworkScore(_ candidate: CandidatePeriod) -> Int {
            let name = normalizedName(candidate)
            return containsAny(name, ["cowork"]) ? 220 : 0
        }

        private func iguanaScore(_ candidate: CandidatePeriod) -> Int {
            let name = normalizedName(candidate)
            return containsAny(name, ["iguana", "necktie"]) ? 220 : 0
        }

        private func extraUsageScore(_ candidate: CandidatePeriod) -> Int {
            let name = normalizedName(candidate)
            if containsAny(name, ["extra", "additional", "bonus"]) { return 220 }
            return containsAny(name, ["five_hour", "seven_day", "weekly", "opus", "sonnet", "oauth", "cowork", "iguana"]) ? 0 : 40
        }

        private func hoursUntilReset(_ candidate: CandidatePeriod) -> Double? {
            guard let resetsAt = candidate.period.resetsAt,
                  let date = UsageResponseParser.parseDate(resetsAt) else { return nil }
            return date.timeIntervalSinceNow / 3600
        }

        private func compareOrder(_ lhs: CandidatePeriod, _ rhs: CandidatePeriod) -> Bool {
            let lReset = lhs.period.resetsAt.flatMap(UsageResponseParser.parseDate)
            let rReset = rhs.period.resetsAt.flatMap(UsageResponseParser.parseDate)
            switch (lReset, rReset) {
            case let (l?, r?):
                if l != r { return l < r }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return normalize(lhs.name) < normalize(rhs.name)
        }

        private func normalizedName(_ candidate: CandidatePeriod) -> String {
            normalize(candidate.name + "_" + candidate.path.joined(separator: "_"))
        }

        private func containsAny(_ value: String, _ patterns: [String]) -> Bool {
            patterns.contains(where: value.contains)
        }

        private func normalize(_ string: String) -> String {
            string
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: "_")
        }

        private struct CandidatePeriod {
            let name: String
            let path: [String]
            let period: UsageResponse.UsagePeriod

            var displayName: String {
                let normalized = name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.isEmpty ? "Scoped" : normalized
            }
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

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

struct SettingsResponse: Codable, Sendable {
    let rateLimitInfo: RateLimitInfo?

    struct RateLimitInfo: Codable, Sendable {
        let messagesRemaining: Int?
        let messageLimit: Int?
        let resetsAt: String?
    }
}

nonisolated struct PrepaidCreditsResponse: Codable, Sendable {
    let amount: Int  // Amount in minor units (cents)
    let currency: String
    let autoReloadSettings: AutoReloadSettings?
    let pendingInvoiceAmountCents: Int?
    let tranches: [CreditTranche]?
    let promoTranches: [CreditTranche]?

    struct AutoReloadSettings: Codable, Sendable {
        let enabled: Bool?
    }

    struct CreditTranche: Codable, Sendable {
        let remainingAmountMinorUnits: Int
        let currency: String
        let grantedAmountMinorUnits: Int
    }
}

nonisolated struct OverageCreditGrantResponse: Codable, Sendable {
    let available: Bool
    let eligible: Bool
    let granted: Bool
    let amountMinorUnits: Int  // Original grant amount in minor units
    let currency: String
}

nonisolated struct OverageSpendLimitResponse: Codable, Sendable {
    let isEnabled: Bool
    let monthlyCreditLimit: Int   // Minor units (cents)
    let currency: String
    let usedCredits: Int          // Minor units (cents)
    let outOfCredits: Bool
    let disabledReason: String?
}
