import Foundation

nonisolated enum GrokAPIError: Error, LocalizedError {
    case unauthorized
    case forbidden
    case rateLimited(TimeInterval?)
    case network(Error)
    case invalidResponse(endpoint: String, statusCode: Int)
    case invalidPayload(String)
    case noWeeklyUsage
    case unsupportedPrincipal
    case noSessionCookies
    case noAccessToken

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            String(localized: "Session expired. Please sign in again.")
        case .forbidden:
            String(localized: "This Grok account cannot access SuperGrok usage.")
        case .rateLimited:
            String(localized: "Grok is rate limiting usage requests. Retrying later.")
        case .network(let error):
            String(localized: "Network error: \(error.localizedDescription)")
        case .invalidResponse(_, let statusCode):
            String(localized: "Invalid response from Grok (HTTP \(statusCode)).")
        case .invalidPayload(let reason):
            String(localized: "Grok changed its usage response: \(reason)")
        case .noWeeklyUsage:
            String(localized: "Weekly SuperGrok usage is not available for this account.")
        case .unsupportedPrincipal:
            String(localized: "Team Grok accounts cannot show personal weekly usage yet.")
        case .noSessionCookies:
            String(localized: "Not authenticated. Please sign in.")
        case .noAccessToken:
            String(localized: "Grok usage API is not connected. Sign in again.")
        }
    }
}

actor GrokAPIClient {
    private let session: URLSession
    private var sessionCookies: String?
    private var accessToken: String?
    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                "Origin": "https://grok.com",
                "Referer": "https://grok.com/"
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

    func setSessionCookies(_ cookies: String) {
        sessionCookies = cookies
    }

    func clearSessionCookies() {
        sessionCookies = nil
        accessToken = nil
    }

    func setAccessToken(_ token: String?) {
        accessToken = token
    }

    func fetchIdentity() async throws -> String {
        let sessionURL = URL(string: "https://accounts.x.ai/api/auth/session")!
        let data = try await get(sessionURL)
        if let identity = GrokIdentityParser.identity(from: data) {
            return identity
        }
        if GrokIdentityParser.hasActiveSession(data) {
            return String(localized: "Signed in")
        }
        throw GrokAPIError.unauthorized
    }

    func fetchWeeklyUsage(planDisplayName: String? = nil) async throws -> GrokUsageData {
        guard accessToken != nil else {
            throw GrokAPIError.noAccessToken
        }
        let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
        let data = try await get(url)
        if let usage = try? GrokUsageParser.parseWeekly(data, planDisplayName: planDisplayName) {
            return usage
        }
        if let usage = GrokUsageParser.parseWeeklyIfPresent(data, planDisplayName: planDisplayName) {
            return usage
        }
        throw GrokAPIError.noWeeklyUsage
    }

    func fetchPlanDisplayName() async throws -> String? {
        guard accessToken != nil else { return nil }
        let url = URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!
        let data = try await get(url)
        return (try? JSONDecoder().decode(GrokSettingsResponseDTO.self, from: data))?.subscription_tier_display
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let accessToken, url.host?.contains("cli-chat-proxy.grok.com") == true {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        } else if let sessionCookies, !sessionCookies.isEmpty {
            request.setValue(sessionCookies, forHTTPHeaderField: "Cookie")
        } else {
            throw GrokAPIError.noAccessToken
        }
        if let host = url.host, host.contains("accounts.x.ai") {
            request.setValue("https://accounts.x.ai", forHTTPHeaderField: "Origin")
            request.setValue("https://accounts.x.ai/", forHTTPHeaderField: "Referer")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GrokAPIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GrokAPIError.invalidResponse(endpoint: url.path, statusCode: -1)
        }
        switch http.statusCode {
        case 200..<300:
            if data.count > 2_000_000 {
                throw GrokAPIError.invalidPayload("response too large")
            }
            return data
        case 401:
            throw GrokAPIError.unauthorized
        case 403:
            throw GrokAPIError.forbidden
        case 429:
            throw GrokAPIError.rateLimited(http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        default:
            throw GrokAPIError.invalidResponse(endpoint: url.path, statusCode: http.statusCode)
        }
    }
}

nonisolated enum GrokIdentityParser {
    static func hasActiveSession(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        if object is NSNull { return false }
        if let dictionary = object as? [String: Any] {
            if dictionary.isEmpty { return false }
            if dictionary["user"] != nil || dictionary["session"] != nil {
                return true
            }
        }
        return identity(from: data) != nil
    }

    static func identity(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let email = firstString(named: ["email", "emailAddress", "user_email"], in: object), email.contains("@") {
            return email
        }
        return firstString(named: ["name", "displayName", "fullName", "username"], in: object)
    }

    static func email(from data: Data) -> String? {
        identity(from: data)
    }

    private static func firstString(named keys: Set<String>, in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                if keys.contains(key), let string = nested as? String, string.contains("@") {
                    return string
                }
                if let found = firstString(named: keys, in: nested) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = firstString(named: keys, in: nested) {
                    return found
                }
            }
        }
        return nil
    }
}
