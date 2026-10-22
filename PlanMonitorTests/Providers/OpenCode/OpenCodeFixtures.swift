import Foundation
@testable import PlanMonitor

/// Console API payloads. Two shapes, both verbatim apart from identities:
///
/// - `captured`: the live account of 2026-10-22, with its `user_id` and email replaced — one member,
///   no budget, nothing spent (a Go-only month).
/// - `docsExample`: the Budgets API reference's own example — $12.50 spent of a $75.25 custom budget.
///
/// No real key appears anywhere in the tests; `testKey` has the shape and nothing else.
enum OpenCodeFixtures {
    static let testKey = "oc_sk_0123456789ab_not-a-real-secret"

    static let captured = #"""
    [{"user_id":"acc_test","email":"member@example.com","limit_micro_cents":null,"spent_micro_cents":"0","exceeded":false,"resets_at":"2026-11-01T00:00:00.000Z","source":null,"updated_at":null}]
    """#

    static let docsExample = #"""
    [{"user_id":"user_alice","email":"alice@example.com","limit_micro_cents":"7525000000","spent_micro_cents":"1250000000","exceeded":false,"resets_at":"2026-10-01T00:00:00.000Z","source":"custom","updated_at":"2026-09-03T12:00:00.000Z"}]
    """#

    /// `GET /inference/go/v1/usage` on the live account, 2026-10-22, verbatim.
    static let goUsage = #"""
    {"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"2026-10-22T22:29:03.000Z"},"weekly":{"status":"ok","percent":0,"resetsAt":"2026-10-26T00:00:00.000Z"},"monthly":{"status":"ok","percent":0,"resetsAt":"2026-11-22T16:42:21.000Z"}}}
    """#

    /// The same shape mid-cycle, with the 5-hour window rate-limited.
    static let goUsageLimited = #"""
    {"usage":{"rolling":{"status":"rate-limited","percent":100,"resetsAt":"2026-10-22T22:29:03.000Z"},"weekly":{"status":"ok","percent":61,"resetsAt":"2026-10-26T00:00:00.000Z"},"monthly":{"status":"ok","percent":24,"resetsAt":"2026-11-22T16:42:21.000Z"}}}
    """#

    static func go(_ json: String) throws -> OpenCodeGoUsage? {
        try JSONDecoder().decode(OpenCodeGoUsageResponse.self, from: Data(json.utf8)).goUsage
    }

    static func members(_ json: String) throws -> [OpenCodeMemberBudget] {
        try JSONDecoder().decode([OpenCodeMemberBudgetDTO].self, from: Data(json.utf8)).map(\.member)
    }

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    static func utc(_ string: String) -> Date {
        OpenCodeMemberBudgetDTO.date(from: string)!
    }
}
