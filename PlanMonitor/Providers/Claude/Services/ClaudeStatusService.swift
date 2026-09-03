import Foundation

struct ClaudeStatusSnapshot: Sendable {
    let status: ClaudeSystemStatus
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
}

enum ClaudeSystemStatus: Sendable {
    case operational
    case degraded
    case outage

    init(indicator: String) {
        switch indicator.lowercased() {
        case "none":
            self = .operational
        case "minor":
            self = .degraded
        case "major", "critical":
            self = .outage
        default:
            self = .degraded
        }
    }
}

final class ClaudeStatusService {
    private let session: URLSession
    private let endpoint = URL(string: "https://status.claude.com/api/v2/status.json")!
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = Self.iso8601WithFractional.date(from: dateString) {
                return date
            }
            if let date = Self.iso8601Basic.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(dateString)"
            )
        }
        self.decoder = decoder
    }

    func fetchStatus() async throws -> ClaudeStatusSnapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try decoder.decode(StatusResponse.self, from: data)
        return ClaudeStatusSnapshot(
            status: ClaudeSystemStatus(indicator: payload.status.indicator),
            sourceUpdatedAt: payload.page?.updatedAt,
            fetchedAt: Date()
        )
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct StatusResponse: Decodable {
    let status: Status
    let page: Page?

    struct Status: Decodable {
        let indicator: String
    }

    struct Page: Decodable {
        let updatedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case updatedAt = "updated_at"
        }
    }
}
