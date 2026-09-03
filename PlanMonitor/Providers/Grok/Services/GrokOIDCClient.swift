import Foundation

nonisolated enum GrokOIDCError: Error, LocalizedError {
    case invalidGrant
    case network(Error)
    case invalidResponse
    case missingAccessToken
    case expired
    case denied
    case authorizationPending

    var errorDescription: String? {
        switch self {
        case .invalidGrant:
            String(localized: "Grok login changed. Sign in again.")
        case .network(let error):
            String(localized: "Network error: \(error.localizedDescription)")
        case .invalidResponse:
            String(localized: "Invalid response from Grok authentication.")
        case .missingAccessToken:
            String(localized: "Grok did not return an access token.")
        case .expired:
            String(localized: "Grok approval timed out. Sign in again.")
        case .denied:
            String(localized: "Grok access was denied.")
        case .authorizationPending:
            String(localized: "Waiting for Grok approval.")
        }
    }
}

nonisolated struct GrokDeviceAuthorization: Sendable {
    var deviceCode: String
    var userCode: String
    var verificationURL: URL
    var expiresAt: Date
    var interval: TimeInterval
}

actor GrokOIDCClient {
    static let scope = "openid profile email offline_access grok-cli:access api:access"

    private let session: URLSession
    private let tokenURL = URL(string: "https://auth.x.ai/oauth2/token")!
    private let deviceCodeURL = URL(string: "https://auth.x.ai/oauth2/device/code")!
    private let userInfoURL = URL(string: "https://auth.x.ai/oauth2/userinfo")!

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config)
        }
    }

    func refresh(credentials: GrokCredentials, now: Date = Date()) async throws -> GrokCredentials {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = [
            "grant_type": "refresh_token",
            "client_id": credentials.clientID,
            "refresh_token": credentials.refreshToken
        ]
        request.httpBody = body
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GrokOIDCError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GrokOIDCError.invalidResponse
        }

        let payload = try? JSONDecoder().decode(OAuthTokenResponseDTO.self, from: data)
        if http.statusCode == 400 || http.statusCode == 401 {
            if payload?.error == "invalid_grant" {
                throw GrokOIDCError.invalidGrant
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            if payload?.error == "invalid_grant" {
                throw GrokOIDCError.invalidGrant
            }
            throw GrokOIDCError.invalidResponse
        }

        guard let accessToken = payload?.access_token, !accessToken.isEmpty else {
            throw GrokOIDCError.missingAccessToken
        }

        let expiresIn = payload?.expires_in ?? 21600
        var updated = credentials
        updated.accessToken = accessToken
        updated.tokenType = payload?.token_type ?? "Bearer"
        updated.accessTokenExpiresAt = now.addingTimeInterval(expiresIn)
        if let refresh = payload?.refresh_token, !refresh.isEmpty {
            updated.refreshToken = refresh
        }
        if let scope = payload?.scope, !scope.isEmpty {
            updated.scopes = scope.split(separator: " ").map(String.init)
        }
        updated.refreshedAt = now
        return updated
    }

    func startDeviceAuthorization(now: Date = Date()) async throws -> GrokDeviceAuthorization {
        var request = URLRequest(url: deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody([
            "client_id": GrokCredentials.expectedClientID,
            "scope": Self.scope
        ])
        let payload = try await post(request)
        guard let deviceCode = payload.device_code, !deviceCode.isEmpty,
              let userCode = payload.user_code,
              let rawURL = payload.verification_uri_complete ?? payload.verification_uri,
              let url = URL(string: rawURL) else {
            throw GrokOIDCError.invalidResponse
        }
        return GrokDeviceAuthorization(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: url,
            expiresAt: now.addingTimeInterval(payload.expires_in ?? 900),
            interval: max(payload.interval ?? 5, 2)
        )
    }

    func pollDeviceAuthorization(
        _ authorization: GrokDeviceAuthorization,
        email: String?,
        now: Date = Date()
    ) async throws -> GrokCredentials {
        var interval = authorization.interval
        while Date() < authorization.expiresAt {
            do {
                var credentials = try await exchangeDeviceCode(authorization.deviceCode, now: now)
                credentials.email = email ?? credentials.email
                if credentials.email == nil {
                    credentials.email = try? await fetchEmail(accessToken: credentials.accessToken)
                }
                return credentials
            } catch GrokOIDCError.authorizationPending {
                try? await Task.sleep(for: .seconds(interval))
            } catch GrokOIDCError.invalidResponse {
                interval += 5
                try? await Task.sleep(for: .seconds(interval))
            }
        }
        throw GrokOIDCError.expired
    }

    private func exchangeDeviceCode(_ deviceCode: String, now: Date) async throws -> GrokCredentials {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody([
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": deviceCode,
            "client_id": GrokCredentials.expectedClientID
        ])
        let payload = try await post(request, allowPending: true)
        guard let accessToken = payload.access_token, !accessToken.isEmpty,
              let refreshToken = payload.refresh_token, !refreshToken.isEmpty else {
            throw GrokOIDCError.missingAccessToken
        }
        return GrokCredentials(
            schemaVersion: GrokCredentials.currentSchemaVersion,
            issuer: GrokCredentials.expectedIssuer,
            clientID: GrokCredentials.expectedClientID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: now.addingTimeInterval(payload.expires_in ?? 21600),
            tokenType: payload.token_type ?? "Bearer",
            scopes: (payload.scope ?? Self.scope).split(separator: " ").map(String.init),
            userID: nil,
            principalID: nil,
            principalType: "User",
            teamID: nil,
            email: nil,
            displayName: nil,
            importedAt: now,
            refreshedAt: now
        )
    }

    func fetchEmail(accessToken: String) async throws -> String? {
        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw GrokOIDCError.network(error)
        }
        return GrokIdentityParser.identity(from: data)
    }

    private func post(_ request: URLRequest, allowPending: Bool = false) async throws -> OAuthTokenResponseDTO {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GrokOIDCError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GrokOIDCError.invalidResponse
        }
        let payload = try? JSONDecoder().decode(OAuthTokenResponseDTO.self, from: data)
        if allowPending {
            switch payload?.error {
            case "authorization_pending":
                throw GrokOIDCError.authorizationPending
            case "slow_down":
                throw GrokOIDCError.invalidResponse
            case "access_denied":
                throw GrokOIDCError.denied
            case "expired_token":
                throw GrokOIDCError.expired
            default:
                break
            }
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            if payload?.error == "invalid_grant" {
                throw GrokOIDCError.invalidGrant
            }
            if allowPending, payload?.error == "authorization_pending" {
                throw GrokOIDCError.authorizationPending
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GrokOIDCError.invalidResponse
        }
        guard let payload else {
            throw GrokOIDCError.invalidResponse
        }
        return payload
    }

    private func formBody(_ fields: [String: String]) -> Data {
        fields
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}
