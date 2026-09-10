import Foundation
import Testing
@testable import PlanTracker

private func key(
    hash: String,
    name: String = "Key",
    limit: Decimal? = nil,
    limitRemaining: Decimal? = nil,
    limitReset: String? = nil,
    includeBYOK: Bool = false,
    usage: Decimal = 0,
    daily: Decimal = 0,
    weekly: Decimal = 0,
    monthly: Decimal = 0,
    byokDaily: Decimal = 0,
    byokWeekly: Decimal = 0,
    byokMonthly: Decimal = 0,
    disabled: Bool = false
) -> APIKeyDTO {
    let json: [String: Any?] = [
        "hash": hash, "name": name, "label": "sk-or-v1-xxx",
        "disabled": disabled,
        "limit": limit.map(NSDecimalNumber.init(decimal:)),
        "limit_remaining": limitRemaining.map(NSDecimalNumber.init(decimal:)),
        "limit_reset": limitReset,
        "include_byok_in_limit": includeBYOK,
        "usage": NSDecimalNumber(decimal: usage),
        "usage_daily": NSDecimalNumber(decimal: daily),
        "usage_weekly": NSDecimalNumber(decimal: weekly),
        "usage_monthly": NSDecimalNumber(decimal: monthly),
        "byok_usage": NSDecimalNumber(decimal: 0),
        "byok_usage_daily": NSDecimalNumber(decimal: byokDaily),
        "byok_usage_weekly": NSDecimalNumber(decimal: byokWeekly),
        "byok_usage_monthly": NSDecimalNumber(decimal: byokMonthly)
    ]
    let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
    return try! JSONDecoder().decode(APIKeyDTO.self, from: data)
}

private func guardrail(
    id: String,
    name: String = "Guardrail",
    limitUSD: Decimal? = 100,
    resetInterval: String? = "monthly",
    includeBYOK: Bool = false
) -> GuardrailDTO {
    let json: [String: Any?] = [
        "id": id, "name": name,
        "limit_usd": limitUSD.map(NSDecimalNumber.init(decimal:)),
        "reset_interval": resetInterval,
        "include_byok_in_budgets": includeBYOK
    ]
    let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
    return try! JSONDecoder().decode(GuardrailDTO.self, from: data)
}

private func assignment(key keyHash: String, guardrail guardrailID: String) -> GuardrailKeyAssignmentDTO {
    let data = try! JSONSerialization.data(withJSONObject: [
        "key_hash": keyHash, "guardrail_id": guardrailID, "key_name": "Key \(keyHash)"
    ])
    return try! JSONDecoder().decode(GuardrailKeyAssignmentDTO.self, from: data)
}

private func assemble(
    credits: CreditsDTO? = nil,
    keys: [APIKeyDTO] = [],
    guardrails: [GuardrailDTO] = [],
    assignments: [GuardrailKeyAssignmentDTO] = [],
    activity: [ActivityRowDTO]? = nil,
    analytics: [AnalyticsRowDTO]? = nil,
    dayAnalytics: [AnalyticsRowDTO]? = nil,
    window: RecentModelsWindow = .fifteenMinutes,
    now: Date = Date(timeIntervalSince1970: 1_756_000_000)
) -> OpenRouterSnapshot {
    OpenRouterBudgetAssembler.assemble(
        credits: credits, keys: keys, guardrails: guardrails, assignments: assignments,
        activity: activity, analytics: analytics, dayAnalytics: dayAnalytics,
        recentModelsWindow: window, guardrailsAvailable: true, now: now
    )
}

/// Builds a minute row in the exact wire shape: `total_usage` a number,
/// `tokens_total`/`request_count` strings, bucket as "yyyy-MM-dd HH:mm:ss" UTC.
private func analyticsRow(model: String, minutesAgo: Int, usage: Double,
                          tokens: Int, requests: Int = 1,
                          now: Date = Date(timeIntervalSince1970: 1_756_000_000)) -> AnalyticsRowDTO {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let bucket = formatter.string(from: now.addingTimeInterval(-Double(minutesAgo) * 60))
    let json = """
    {"date__minute":"\(bucket)","model":"\(model)","total_usage":\(usage),\
    "tokens_total":"\(tokens)","request_count":"\(requests)"}
    """
    return try! JSONDecoder().decode(AnalyticsRowDTO.self, from: Data(json.utf8))
}

private func activityRows(_ amounts: [Decimal]) -> [ActivityRowDTO] {
    let json = "[" + amounts.map { "{\"usage\":\($0)}" }.joined(separator: ",") + "]"
    return try! JSONDecoder().decode([ActivityRowDTO].self, from: Data(json.utf8))
}

@Suite("Guardrail budget assembly")
struct GuardrailAssemblyTests {

    /// THE regression test for build plan §6.2. Guardrail budgets are enforced
    /// per-key, not as a shared pot: four keys at 30% of a $100 guardrail is 30%,
    /// not 120%. Summing would be catastrophically misleading.
    @Test("Four keys at 30% each yield worstFraction 0.30, not 1.20")
    func perKeyEnforcementNotSummed() {
        let keys = (1...4).map { key(hash: "k\($0)", monthly: 30) }
        let snapshot = assemble(
            keys: keys,
            guardrails: [guardrail(id: "g1", limitUSD: 100, resetInterval: "monthly")],
            assignments: (1...4).map { assignment(key: "k\($0)", guardrail: "g1") }
        )
        let budget = try! #require(snapshot.guardrailBudgets.first)
        #expect(budget.members.count == 4)
        #expect(abs(budget.worstFraction - 0.30) < 0.0001)
        #expect(budget.worstFraction < 1.0)
    }

    @Test("Headline is the maximum member, not the mean")
    func headlineIsMaximum() {
        let keys = [key(hash: "a", monthly: 61), key(hash: "b", monthly: 30), key(hash: "c", monthly: 12)]
        let snapshot = assemble(
            keys: keys,
            guardrails: [guardrail(id: "g1", limitUSD: 100)],
            assignments: [assignment(key: "a", guardrail: "g1"),
                          assignment(key: "b", guardrail: "g1"),
                          assignment(key: "c", guardrail: "g1")]
        )
        let budget = try! #require(snapshot.guardrailBudgets.first)
        #expect(abs(budget.worstFraction - 0.61) < 0.0001)
        // Sorted descending so the closest-to-breaking key is first.
        #expect(budget.members.map(\.keyHash) == ["a", "b", "c"])
    }

    @Test("reset_interval selects the matching usage window", arguments: [
        ("daily", Decimal(5)), ("weekly", Decimal(20)), ("monthly", Decimal(80))
    ])
    func intervalSelectsMatchingWindow(interval: String, expected: Decimal) {
        let k = key(hash: "a", daily: 5, weekly: 20, monthly: 80)
        let snapshot = assemble(
            keys: [k],
            guardrails: [guardrail(id: "g1", limitUSD: 100, resetInterval: interval)],
            assignments: [assignment(key: "a", guardrail: "g1")]
        )
        let member = try! #require(snapshot.guardrailBudgets.first?.members.first)
        #expect(member.spent == expected)
    }

    @Test("include_byok_in_budgets adds BYOK spend")
    func byokCounted() {
        let k = key(hash: "a", monthly: 40, byokMonthly: 25)
        let without = assemble(keys: [k], guardrails: [guardrail(id: "g1", includeBYOK: false)],
                               assignments: [assignment(key: "a", guardrail: "g1")])
        let with = assemble(keys: [k], guardrails: [guardrail(id: "g1", includeBYOK: true)],
                            assignments: [assignment(key: "a", guardrail: "g1")])
        #expect(without.guardrailBudgets.first?.members.first?.spent == 40)
        #expect(with.guardrailBudgets.first?.members.first?.spent == 65)
    }

    @Test("Policy-only guardrail (no limit_usd) produces no budget")
    func policyOnlyGuardrailSkipped() {
        let snapshot = assemble(
            keys: [key(hash: "a", monthly: 10)],
            guardrails: [guardrail(id: "g1", limitUSD: nil, resetInterval: nil)],
            assignments: [assignment(key: "a", guardrail: "g1")]
        )
        #expect(snapshot.guardrailBudgets.isEmpty)
    }

    @Test("Guardrail with no assignments is listed as unassigned, not 0%-of-nothing")
    func unassignedGuardrailListed() {
        let snapshot = assemble(guardrails: [guardrail(id: "g1", limitUSD: 50)])
        let budget = try! #require(snapshot.guardrailBudgets.first)
        #expect(budget.members.isEmpty)
        #expect(budget.hasMembers == false)
        #expect(budget.limit == 50)
    }

    @Test("Assignment referencing an unknown key is skipped without crashing")
    func danglingAssignmentSkipped() {
        let snapshot = assemble(
            keys: [key(hash: "a", monthly: 10)],
            guardrails: [guardrail(id: "g1")],
            assignments: [assignment(key: "a", guardrail: "g1"),
                          assignment(key: "ghost", guardrail: "g1"),
                          assignment(key: "a", guardrail: "missing-guardrail")]
        )
        #expect(snapshot.guardrailBudgets.first?.members.count == 1)
    }

    @Test("A key with both a personal cap and a guardrail yields both gauges")
    func bothGaugesShown() {
        let k = key(hash: "a", limit: 50, limitRemaining: 5, limitReset: "monthly", monthly: 45)
        let snapshot = assemble(
            keys: [k],
            guardrails: [guardrail(id: "g1", limitUSD: 100)],
            assignments: [assignment(key: "a", guardrail: "g1")]
        )
        #expect(snapshot.keyBudgets.count == 1)
        #expect(snapshot.guardrailBudgets.first?.members.count == 1)
        // Key cap at 90% binds before the guardrail at 45%.
        let member = try! #require(snapshot.guardrailBudgets.first?.members.first)
        #expect(member.supersededByKeyLimit)
    }

    @Test("Empty account yields a valid empty snapshot")
    func emptyAccount() {
        let snapshot = assemble()
        #expect(snapshot.keyBudgets.isEmpty)
        #expect(snapshot.guardrailBudgets.isEmpty)
        #expect(snapshot.isEmpty)
    }
}

@Suite("Key budget assembly")
struct KeyBudgetTests {

    @Test("Uncapped key is spend-only, never a gauge")
    func uncappedKeyHasNoGauge() {
        let snapshot = assemble(keys: [key(hash: "a", limit: nil, usage: 12)])
        #expect(snapshot.keyBudgets.isEmpty)
        #expect(snapshot.uncappedKeys.count == 1)
        #expect(snapshot.uncappedKeys.first?.spentInWindow == 12)
    }

    @Test("limit_remaining is authoritative over recomputation")
    func trustsLimitRemaining() {
        // usage_monthly disagrees with limit_remaining; the server value wins.
        let k = key(hash: "a", limit: 100, limitRemaining: 25, limitReset: "monthly", monthly: 999)
        let budget = try! #require(assemble(keys: [k]).keyBudgets.first)
        #expect(budget.spent == 75)
        #expect(budget.remaining == 25)
        #expect(budget.isApproximate == false)
    }

    @Test("Absent limit_remaining falls back to usage and marks the row approximate")
    func fallsBackToUsage() {
        let k = key(hash: "a", limit: 100, limitRemaining: nil, limitReset: "daily", daily: 30)
        let budget = try! #require(assemble(keys: [k]).keyBudgets.first)
        #expect(budget.spent == 30)
        #expect(budget.isApproximate)
    }

    @Test("Fallback adds BYOK only when the key opts in")
    func fallbackHonoursBYOKFlag() {
        let k = key(hash: "a", limit: 100, limitRemaining: nil, limitReset: "daily",
                    includeBYOK: true, daily: 30, byokDaily: 10)
        let budget = try! #require(assemble(keys: [k]).keyBudgets.first)
        #expect(budget.spent == 40)
    }

    @Test("Overspend reports a fraction above 1 rather than clamping")
    func overspendNotClamped() {
        let k = key(hash: "a", limit: 100, limitRemaining: -20, limitReset: "monthly")
        let budget = try! #require(assemble(keys: [k]).keyBudgets.first)
        #expect(budget.usedFraction > 1.0)
    }

    @Test("Keys are sorted worst-first")
    func sortedWorstFirst() {
        let keys = [
            key(hash: "low", limit: 100, limitRemaining: 90, limitReset: "monthly"),
            key(hash: "high", limit: 100, limitRemaining: 5, limitReset: "monthly"),
            key(hash: "mid", limit: 100, limitRemaining: 50, limitReset: "monthly")
        ]
        #expect(assemble(keys: keys).keyBudgets.map(\.keyHash) == ["high", "mid", "low"])
    }

    @Test("Zero limit is treated as uncapped, never divided by")
    func zeroLimitNotDivided() {
        let snapshot = assemble(keys: [key(hash: "a", limit: 0, usage: 5)])
        #expect(snapshot.keyBudgets.isEmpty)
        #expect(snapshot.uncappedKeys.count == 1)
    }
}


@Suite("Recent spend windows")
struct SpendWindowTests {

    /// Current-month spend comes from the live per-key counters, so it needs no extra
    /// request and already includes today.
    @Test("This month is the sum of per-key monthly usage")
    func thisMonthSumsKeys() {
        let snapshot = assemble(keys: [
            key(hash: "a", daily: 2, monthly: 10),
            key(hash: "b", daily: 1, monthly: Decimal(string: "5.5")!)
        ])
        #expect(snapshot.spentThisMonth == Decimal(string: "15.5")!)
    }

    /// /activity ends yesterday, so today's per-key total is added to make the window
    /// a genuine rolling 30 days.
    @Test("Last 30 days is activity plus today")
    func last30AddsToday() {
        let snapshot = assemble(
            keys: [key(hash: "a", daily: 3), key(hash: "b", daily: Decimal(string: "0.5")!)],
            activity: activityRows([10, 20, Decimal(string: "1.25")!])
        )
        #expect(snapshot.spentLast30Days == Decimal(string: "34.75")!)
    }

    @Test("Without activity the 30-day figure is nil, never a wrong number")
    func noActivityMeansNil() {
        let snapshot = assemble(keys: [key(hash: "a", daily: 2, monthly: 10)], activity: nil)
        #expect(snapshot.spentLast30Days == nil)
        #expect(snapshot.spentThisMonth == 10)   // month still works, it needs no activity
    }

    @Test("An empty account reports no month figure rather than zero")
    func emptyAccountNoMonth() {
        #expect(assemble().spentThisMonth == nil)
    }
}


@Suite("Trailing spend windows and recent models")
struct RecentActivityTests {
    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    /// One 60-minute query serves both figures: the hour is every row, the 15 minutes
    /// is the subset inside that window.
    @Test("15-minute and hourly totals come from the same rows")
    func windowsSplitCorrectly() {
        let snapshot = assemble(analytics: [
            analyticsRow(model: "a/one", minutesAgo: 2, usage: 0.01, tokens: 100),
            analyticsRow(model: "a/one", minutesAgo: 10, usage: 0.02, tokens: 200),
            analyticsRow(model: "b/two", minutesAgo: 40, usage: 0.05, tokens: 300)
        ], now: now)
        #expect(snapshot.spentLast15Minutes == Decimal(string: "0.03")!)
        #expect(snapshot.spentLastHour == Decimal(string: "0.08")!)
    }

    /// "Last models called" is recency order, not biggest spender first.
    @Test("Models are ordered by most recent call")
    func orderedByRecency() {
        let snapshot = assemble(analytics: [
            analyticsRow(model: "big/spender", minutesAgo: 12, usage: 5.0, tokens: 10),
            analyticsRow(model: "recent/one", minutesAgo: 1, usage: 0.001, tokens: 10)
        ], now: now)
        #expect(snapshot.recentModels.map(\.model) == ["recent/one", "big/spender"])
    }

    @Test("Rows for the same model are merged across minutes")
    func mergesModelRows() {
        let snapshot = assemble(analytics: [
            analyticsRow(model: "a/one", minutesAgo: 2, usage: 0.01, tokens: 100, requests: 2),
            analyticsRow(model: "a/one", minutesAgo: 5, usage: 0.02, tokens: 250, requests: 3)
        ], now: now)
        #expect(snapshot.recentModels.count == 1)
        let model = try! #require(snapshot.recentModels.first)
        #expect(model.spend == Decimal(string: "0.03")!)
        #expect(model.tokens == 350)
        #expect(model.requests == 5)
    }

    /// Models only in the 15-60 minute range still count toward the hour but must not
    /// appear in a list described as "the last 15 minutes".
    @Test("Older models count toward the hour but are not listed")
    func olderModelsExcludedFromList() {
        let snapshot = assemble(analytics: [
            analyticsRow(model: "old/model", minutesAgo: 45, usage: 0.5, tokens: 999)
        ], now: now)
        #expect(snapshot.recentModels.isEmpty)
        #expect(snapshot.spentLastHour == Decimal(string: "0.5")!)
        #expect(snapshot.spentLast15Minutes == 0)
    }

    /// Uncapped on purpose: the section answers "what have I been running", so a model used
    /// inside the window must never be hidden by how many others were.
    @Test("Every model in the window is listed")
    func listsEveryModelInTheWindow() {
        let rows = (1...9).map { analyticsRow(model: "v/m\($0)", minutesAgo: $0, usage: 0.001, tokens: 10) }
        let listed = assemble(analytics: rows, window: .fifteenMinutes, now: now).recentModels
        #expect(listed.count == 9)
        #expect(Set(listed.map(\.model)) == Set(rows.compactMap(\.model)))
    }

    /// The case that made a just-switched model invisible: hourly buckets tie on `lastCalledAt`,
    /// so the cheapest model sorted last and fell off the end of a five-row cap.
    @Test("A newly adopted model in a shared bucket is still listed")
    func newModelSharingABucketIsListed() {
        let rows = (1...8).map { analyticsRow(model: "old/m\($0)", minutesAgo: 30, usage: 5.0, tokens: 1000) }
            + [analyticsRow(model: "brand/new", minutesAgo: 30, usage: 0.0001, tokens: 5)]
        let listed = assemble(dayAnalytics: rows, window: .threeHours, now: now).recentModels
        #expect(listed.map(\.model).contains("brand/new"))
    }

    @Test("Without analytics the trailing figures are nil, never zero")
    func nilWithoutAnalytics() {
        let snapshot = assemble(analytics: nil)
        #expect(snapshot.spentLast15Minutes == nil)
        #expect(snapshot.spentLastHour == nil)
        #expect(snapshot.recentModels.isEmpty)
    }

    /// The API returns tokens and request counts as strings but usage as a number.
    @Test("String-typed metrics decode as exactly as numeric ones")
    func lenientNumberDecoding() {
        let snapshot = assemble(analytics: [
            analyticsRow(model: "a/one", minutesAgo: 1, usage: 0.010467, tokens: 690_584)
        ], now: now)
        let model = try! #require(snapshot.recentModels.first)
        #expect(model.tokens == 690_584)
        #expect(model.spend == Decimal(string: "0.010467")!)
    }

    @Test("Model display name drops the vendor prefix")
    func displayNameSplitsVendor() {
        let usage = ModelUsage(model: "z-ai/glm-5.3-flash", spend: 0, tokens: 0,
                               requests: 0, lastCalledAt: now)
        #expect(usage.displayName == "glm-5.3-flash")
        #expect(usage.vendor == "z-ai")
    }
}


@Suite("Configurable recent-models window")
struct RecentModelsWindowTests {
    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    /// A model called 20 minutes ago is outside a 15-minute window and inside a
    /// 30-minute one — the window is what decides, not a fixed constant.
    @Test("The chosen window decides what is listed")
    func windowGovernsInclusion() {
        let rows = [analyticsRow(model: "a/one", minutesAgo: 20, usage: 0.01, tokens: 10)]
        #expect(assemble(analytics: rows, window: .fifteenMinutes, now: now).recentModels.isEmpty)
        #expect(assemble(analytics: rows, window: .thirtyMinutes, now: now).recentModels.count == 1)
    }

    /// Windows over an hour read the hourly feed, because the minute feed only reaches
    /// back 60 minutes.
    @Test("Long windows read the hourly feed, short ones the minute feed")
    func picksTheRightFeed() {
        let minuteRows = [analyticsRow(model: "minute/model", minutesAgo: 5, usage: 0.01, tokens: 10)]
        let hourRows = [analyticsRow(model: "hour/model", minutesAgo: 300, usage: 0.02, tokens: 20)]

        let short = assemble(analytics: minuteRows, dayAnalytics: hourRows,
                             window: .fifteenMinutes, now: now)
        #expect(short.recentModels.map(\.model) == ["minute/model"])

        let long = assemble(analytics: minuteRows, dayAnalytics: hourRows,
                            window: .sixHours, now: now)
        #expect(long.recentModels.map(\.model) == ["hour/model"])
    }

    /// An hourly bucket is stamped at the start of its hour, so the current partial
    /// hour must not be discarded for sitting fractionally outside the cutoff.
    @Test("The current partial bucket is not dropped")
    func partialBucketKept() {
        // 179 minutes ago is just inside a 3-hour window once bucket length is allowed for.
        let rows = [analyticsRow(model: "edge/model", minutesAgo: 179, usage: 0.01, tokens: 10)]
        #expect(assemble(dayAnalytics: rows, window: .threeHours, now: now).recentModels.count == 1)
    }

    @Test("Elapsed time renders as h:mm")
    func elapsedFormatting() {
        #expect(ElapsedFormatter.string(since: now.addingTimeInterval(-180), now: now) == "00:03")
        #expect(ElapsedFormatter.string(since: now.addingTimeInterval(-9_660), now: now) == "02:41")
        #expect(ElapsedFormatter.string(since: now.addingTimeInterval(60), now: now) == "00:00")
    }

    @Test("Every window maps to a distinct label and minute count")
    func windowsAreDistinct() {
        let all = RecentModelsWindow.allCases
        #expect(Set(all.map(\.minutes)).count == all.count)
        #expect(Set(all.map(\.displayName)).count == all.count)
        #expect(all.filter(\.usesMinuteGranularity).map(\.minutes) == [15, 30, 60])
    }
}
