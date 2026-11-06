import Foundation
@testable import PlanMonitor

/// Plays a queue of answers from x.ai's token endpoint and records what was sent. The shared
/// `StubURLProtocol` holds one fixed answer, and a poll needs a sequence. Tests run in parallel, so
/// queues are keyed by a per-test token, as there.
final class GrokOIDCStub: URLProtocol, @unchecked Sendable {
    enum Answer: Sendable {
        case json(status: Int, String)
        case networkFailure
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: [Answer]] = [:]
    nonisolated(unsafe) private static var bodies: [String: [String]] = [:]

    static func session(_ token: String, answers queue: [Answer]) -> URLSession {
        lock.lock(); answers[token] = queue; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrokOIDCStub.self]
        config.httpAdditionalHeaders = ["X-Test-Case": token]
        return URLSession(configuration: config)
    }

    static func enqueue(_ answer: Answer, for token: String) {
        lock.lock(); answers[token, default: []].append(answer); lock.unlock()
    }

    /// The form bodies sent to the token endpoint, decoded as a server would read them.
    static func forms(for token: String) -> [[String: String]] {
        lock.lock(); defer { lock.unlock() }
        return (bodies[token] ?? []).map { body in
            var fields: [String: String] = [:]
            for pair in body.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                // A form decoder reads a raw `+` as a space, which is what corrupts a token.
                let spaced = parts[1].replacingOccurrences(of: "+", with: " ")
                fields[parts[0]] = spaced.removingPercentEncoding ?? spaced
            }
            return fields
        }
    }

    private static func next(for token: String, body: String) -> Answer? {
        lock.lock(); defer { lock.unlock() }
        bodies[token, default: []].append(body)
        guard var queue = answers[token], !queue.isEmpty else { return nil }
        let answer = queue.removeFirst()
        answers[token] = queue
        return answer
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// URLSession hands a protocol its body as a stream.
    private func readBody() -> String {
        guard let stream = request.httpBodyStream else {
            return request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "X-Test-Case") ?? ""
        switch Self.next(for: token, body: readBody()) {
        case .json(let status, let json):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .networkFailure, nil:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    override func stopLoading() {}
}

/// What x.ai answered, field for field, in the live run of 2026-11-06. Tokens replaced.
enum GrokOIDCFixtures {
    static func tokenAnswer(access: String = "access-1", refresh: String = "refresh-1") -> String {
        #"{"access_token":"\#(access)","expires_in":21600,"id_token":"id","refresh_token":"\#(refresh)","scope":"openid profile email offline_access grok-cli:access api:access","token_type":"Bearer"}"#
    }

    static let userInfo = #"{"email":"someone@example.com","email_verified":true,"family_name":"One","given_name":"Some","name":"Some One","sub":"user-1"}"#

    static func credentials(refresh: String = "refresh-0", expiresIn: TimeInterval = -60) -> GrokCredentials {
        GrokCredentials(
            schemaVersion: GrokCredentials.currentSchemaVersion,
            issuer: GrokCredentials.expectedIssuer,
            clientID: GrokCredentials.expectedClientID,
            accessToken: "access-0",
            refreshToken: refresh,
            accessTokenExpiresAt: Date().addingTimeInterval(expiresIn),
            tokenType: "Bearer",
            scopes: ["openid"],
            userID: nil,
            principalID: nil,
            principalType: "User",
            teamID: nil,
            email: "someone@example.com",
            displayName: nil,
            importedAt: Date(),
            refreshedAt: nil
        )
    }

    static func authorization(expiresIn: TimeInterval = 60) -> GrokDeviceAuthorization {
        GrokDeviceAuthorization(
            deviceCode: "device-1",
            userCode: "ABCD-EFGH",
            verificationURL: URL(string: "https://accounts.x.ai/oauth2/device")!,
            expiresAt: Date().addingTimeInterval(expiresIn),
            interval: 5
        )
    }
}
