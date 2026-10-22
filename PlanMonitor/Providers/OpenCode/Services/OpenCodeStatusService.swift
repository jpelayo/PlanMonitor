import Foundation

enum OpenCodeSystemStatus: Sendable {
    case operational
    case degraded
    case outage

    /// The status page's own words. Anything new reads as degraded: "something may be wrong" is
    /// safer than a green pill for a state nobody has seen yet.
    init(status: String) {
        switch status.lowercased() {
        case "operational": self = .operational
        case "outage": self = .outage
        default: self = .degraded
        }
    }
}

/// `status.opencode.ai`'s own JSON, `GET /api/status`: a top-level `status` (`operational`,
/// `degraded`, `outage`) over components for the console, inference, Go and pay-as-you-go, each
/// broken down per model. Only the top-level rollup is read — "something is wrong" beats
/// per-component precision, the house rule for every status pill.
///
/// A copy of the other providers' status services rather than a shared one, so no pill that works
/// today is touched by this provider.
final class OpenCodeStatusService {
    private let session: URLSession
    private let endpoint = URL(string: "https://status.opencode.ai/api/status")!
    /// The human-readable page behind the pill; opened in the browser when the pill is clicked.
    static let statusPageURL = URL(string: "https://status.opencode.ai/")!

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
    }

    func fetchStatus() async throws -> OpenCodeSystemStatus {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.parse(data)
    }

    /// The rollup alone; the per-model breakdown that makes up most of the document is skipped.
    static func parse(_ data: Data) throws -> OpenCodeSystemStatus {
        let payload = try JSONDecoder().decode(StatusResponse.self, from: data)
        return OpenCodeSystemStatus(status: payload.status)
    }
}

private struct StatusResponse: Decodable {
    let status: String
}
