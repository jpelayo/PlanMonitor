import Foundation

nonisolated struct GrokStatusSnapshot: Sendable {
    let status: GrokSystemStatus
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
}

nonisolated enum GrokSystemStatus: Sendable {
    case operational
    case degraded
    case outage

    /// Severity as the x.ai feed publishes it in `<category>`: `outage`, `disruption`, `info`.
    init(severity: String) {
        switch severity.lowercased() {
        case "outage":
            self = .outage
        case "disruption", "info":
            self = .degraded
        default:
            self = .degraded
        }
    }

    /// Ordering for "worst active incident wins".
    fileprivate var rank: Int {
        switch self {
        case .operational: 0
        case .degraded: 1
        case .outage: 2
        }
    }
}

/// status.x.ai is a custom Next.js site with no JSON API, and every HTML/RSC route sits behind a
/// Cloudflare challenge that rejects non-browser clients. The site-wide RSS feed is the one
/// machine-readable surface URLSession can fetch (verified 2026-09-03 with the default UA).
final class GrokStatusService {
    private let session: URLSession
    private let endpoint = URL(string: "https://status.x.ai/feed.xml")!

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
    }

    func fetchStatus() async throws -> GrokStatusSnapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try GrokStatusFeedParser.parse(data, fetchedAt: Date())
    }
}

/// The feed covers every x.ai product, one `<item>` per incident. Only items whose `<link>` lives
/// under `/grok-com/` (the grok.com web product) count here. Each item carries two `<category>`
/// values: the severity (`outage` / `disruption` / `info`) while the incident is open, replaced by
/// `available` once resolved, plus the state (`active` / `resolved`). The channel's
/// `<lastBuildDate>` is the source timestamp; it is RFC 822, as RSS 2.0 requires.
nonisolated enum GrokStatusFeedParser {
    static let productPathPrefix = "/grok-com/"

    enum ParseError: Error {
        case malformedFeed
    }

    static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> GrokStatusSnapshot {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawChannel else {
            throw ParseError.malformedFeed
        }

        let active = delegate.items.filter { item in
            guard let path = URL(string: item.link)?.path else { return false }
            return path.hasPrefix(productPathPrefix) && item.categories.contains("active")
        }

        let status = active
            .compactMap { item -> GrokSystemStatus? in
                item.categories.first { $0 != "active" && $0 != "resolved" }
                    .map(GrokSystemStatus.init(severity:))
            }
            .max { $0.rank < $1.rank }
            ?? (active.isEmpty ? .operational : .degraded)

        return GrokStatusSnapshot(
            status: status,
            sourceUpdatedAt: delegate.lastBuildDate.flatMap(Self.rfc822Date),
            fetchedAt: fetchedAt
        )
    }

    private static func rfc822Date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string.trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return nil
    }

    struct Item {
        var link = ""
        var categories: [String] = []
    }

    private final class FeedDelegate: NSObject, XMLParserDelegate {
        var items: [Item] = []
        var lastBuildDate: String?
        var sawChannel = false

        private var current: Item?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            text = ""
            switch elementName {
            case "channel":
                sawChannel = true
            case "item":
                current = Item()
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "item":
                if let current { items.append(current) }
                self.current = nil
            case "link":
                current?.link = value
            case "category":
                current?.categories.append(value.lowercased())
            case "lastBuildDate":
                if current == nil { lastBuildDate = value }
            default:
                break
            }
            text = ""
        }
    }
}
