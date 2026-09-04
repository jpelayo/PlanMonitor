import Foundation
import Testing
@testable import PlanTracker

/// Fixtures mirror the live `https://status.x.ai/feed.xml` shape captured 2026-09-03: one
/// `<item>` per incident across every product, two `<category>` values per item.
struct GrokStatusFeedParserTests {
    @Test func activeOutageOnGrokWebIsOutage() throws {
        let snapshot = try GrokStatusFeedParser.parse(Self.feed([
            Self.item(product: "grok-com", severity: "outage", state: "active"),
        ]))
        #expect(snapshot.status == .outage)
    }

    @Test func activeDisruptionIsDegraded() throws {
        let snapshot = try GrokStatusFeedParser.parse(Self.feed([
            Self.item(product: "grok-com", severity: "disruption", state: "active"),
        ]))
        #expect(snapshot.status == .degraded)
    }

    @Test func worstActiveIncidentWins() throws {
        let snapshot = try GrokStatusFeedParser.parse(Self.feed([
            Self.item(product: "grok-com", severity: "info", state: "active"),
            Self.item(product: "grok-com", severity: "outage", state: "active"),
        ]))
        #expect(snapshot.status == .outage)
    }

    @Test func resolvedIncidentsAreOperational() throws {
        let snapshot = try GrokStatusFeedParser.parse(Self.feed([
            Self.item(product: "grok-com", severity: "available", state: "resolved"),
            Self.item(product: "grok-com", severity: "available", state: "resolved"),
        ]))
        #expect(snapshot.status == .operational)
    }

    @Test func otherProductsDoNotCount() throws {
        let snapshot = try GrokStatusFeedParser.parse(Self.feed([
            Self.item(product: "ios-app", severity: "outage", state: "active"),
            Self.item(product: "android-app", severity: "outage", state: "active"),
            Self.item(product: "us-east-1.api.x.ai", severity: "outage", state: "active"),
        ]))
        #expect(snapshot.status == .operational)
    }

    @Test func emptyFeedIsOperational() throws {
        let snapshot = try GrokStatusFeedParser.parse(Self.feed([]))
        #expect(snapshot.status == .operational)
    }

    @Test func lastBuildDateIsTheSourceTimestamp() throws {
        let snapshot = try GrokStatusFeedParser.parse(Self.feed([]))
        let updated = try #require(snapshot.sourceUpdatedAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: updated)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 3)
        #expect(parts.hour == 14)
        #expect(parts.minute == 50)
        #expect(parts.second == 13)
    }

    @Test func malformedFeedThrows() {
        #expect(throws: (any Error).self) {
            try GrokStatusFeedParser.parse(Data("not xml at all".utf8))
        }
    }

    @Test func nonFeedXMLThrows() {
        #expect(throws: (any Error).self) {
            try GrokStatusFeedParser.parse(Data("<html><body>Attention Required!</body></html>".utf8))
        }
    }

    // MARK: - Fixtures

    private static func feed(_ items: [String]) -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
          <channel>
            <title>SpaceXAI System Status</title>
            <link>https://status.x.ai</link>
            <atom:link href="https://status.x.ai/feed.xml" rel="self" type="application/rss+xml" />
            <lastBuildDate>Thu, 03 Sep 2026 14:50:13 GMT</lastBuildDate>
            <ttl>30</ttl>
        \(items.joined(separator: "\n"))
          </channel>
        </rss>
        """
        return Data(xml.utf8)
    }

    private static func item(product: String, severity: String, state: String) -> String {
        """
            <item>
              <title>[Product] Incident</title>
              <link>https://status.x.ai/\(product)/INC0000</link>
              <guid isPermaLink="false">INC0000</guid>
              <description><![CDATA[<h3>Status: \(state.uppercased())</h3><p>Severity: \(severity)</p>]]></description>
              <pubDate>Thu, 03 Sep 2026 13:30:00 GMT</pubDate>
              <category>\(severity)</category>
              <category>\(state)</category>
            </item>
        """
    }
}
