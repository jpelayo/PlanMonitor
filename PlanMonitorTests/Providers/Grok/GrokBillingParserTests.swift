import Foundation
import Testing
@testable import PlanTracker

struct GrokBillingParserTests {
    @Test func parsesLiveWeeklyPayload() throws {
        let data = Self.weeklyJSON.data(using: .utf8)!
        let usage = try GrokUsageParser.parseWeekly(data, planDisplayName: "SuperGrok")
        #expect(usage.weeklyUtilization == 0.09)
        #expect(usage.products.count == 2)
        #expect(usage.products[0].product == "GrokBuild")
        #expect(usage.products[0].utilization == 0.08)
        #expect(usage.products[1].product == "GrokChat")
        #expect(usage.planDisplayName == "SuperGrok")
        #expect(usage.prepaidBalance == 0)
        #expect(usage.isUnifiedBilling)
        let end = try #require(usage.weeklyResetsAt)
        #expect(Calendar(identifier: .gregorian).component(.day, from: end) == 29)
    }

    @Test func omittedPercentFallsBackToProductSum() throws {
        let json = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-22T15:42:56Z","end":"2026-08-29T15:42:56Z"},"productUsage":[{"product":"GrokBuild","usagePercent":5},{"product":"GrokChat","usagePercent":1}]}}
        """
        let usage = try GrokUsageParser.parseWeekly(Data(json.utf8))
        #expect(usage.usedPercent == 6)
    }

    @Test func omittedPercentAndProductsYieldZero() throws {
        let json = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-22T15:42:56Z","end":"2026-08-29T15:42:56Z"}}}
        """
        let usage = try GrokUsageParser.parseWeekly(Data(json.utf8))
        #expect(usage.weeklyUtilization == 0)
    }

    @Test func unknownProductsSurvive() throws {
        let json = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-22T15:42:56Z","end":"2026-08-29T15:42:56Z"},"creditUsagePercent":3,"productUsage":[{"product":"Imagine","usagePercent":3}]}}
        """
        let usage = try GrokUsageParser.parseWeekly(Data(json.utf8))
        #expect(usage.products.first?.product == "Imagine")
        #expect(usage.products.first?.displayName == "Imagine")
    }

    @Test func nonweeklyPeriodIsRejected() {
        let json = """
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY","start":"2026-08-01T00:00:00Z","end":"2026-09-01T00:00:00Z"},"creditUsagePercent":10}}
        """
        #expect(throws: GrokUsageParserError.noWeeklyUsage) {
            try GrokUsageParser.parseWeekly(Data(json.utf8))
        }
    }

    @Test func monthlyZeroLimitIsRejected() {
        let json = """
        {"config":{"monthlyLimit":{"val":0},"used":{"val":185},"billingPeriodStart":"2026-08-01T00:00:00Z","billingPeriodEnd":"2026-09-01T00:00:00Z"}}
        """
        #expect(throws: GrokUsageParserError.noWeeklyUsage) {
            try GrokUsageParser.parseMonthly(Data(json.utf8))
        }
    }

    @Test func monthlyPositiveLimitParses() throws {
        let json = """
        {"config":{"monthlyLimit":{"val":15000},"used":{"val":10635},"billingPeriodStart":"2026-08-01T00:00:00Z","billingPeriodEnd":"2026-09-01T00:00:00Z"}}
        """
        let usage = try GrokUsageParser.parseMonthly(Data(json.utf8))
        #expect(usage.monthlyLimit == 15000)
        #expect(usage.monthlyUsed == 10635)
        #expect(usage.weeklyUtilization == nil)
    }

    @Test func settingsNameParses() {
        let json = #"{"subscription_tier_display":"SuperGrok"}"#
        #expect(GrokUsageParser.parsePlanDisplayName(Data(json.utf8)) == "SuperGrok")
    }

    private static let weeklyJSON = """
    {
      "config": {
        "currentPeriod": {
          "type": "USAGE_PERIOD_TYPE_WEEKLY",
          "start": "2026-08-22T15:42:56.116027+00:00",
          "end": "2026-08-29T15:42:56.116027+00:00"
        },
        "creditUsagePercent": 9.0,
        "onDemandCap": { "val": 0 },
        "onDemandUsed": { "val": 0 },
        "productUsage": [
          { "product": "GrokBuild", "usagePercent": 8.0 },
          { "product": "GrokChat", "usagePercent": 1.0 }
        ],
        "isUnifiedBillingUser": true,
        "prepaidBalance": { "val": 0 },
        "topUpMethod": "TOP_UP_METHOD_SAVED_PAYMENT_METHOD",
        "billingPeriodStart": "2026-08-22T15:42:56.116027+00:00",
        "billingPeriodEnd": "2026-08-29T15:42:56.116027+00:00"
      }
    }
    """
}
