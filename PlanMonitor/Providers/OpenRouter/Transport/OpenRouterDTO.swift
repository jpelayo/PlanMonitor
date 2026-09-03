import Foundation

// Wire types for the OpenRouter management API. Decoding is deliberately lenient about
// unknown fields (Swift's synthesised Decodable ignores them) and strict about the
// handful of fields the app actually depends on.

nonisolated struct DataEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T
    let totalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case data
        case totalCount = "total_count"
    }
}

/// `GET /credits`
nonisolated struct CreditsDTO: Decodable, Sendable {
    let totalCredits: Decimal
    let totalUsage: Decimal

    private enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}

/// `GET /key` — used only to validate a pasted key.
nonisolated struct CurrentKeyDTO: Decodable, Sendable {
    let label: String?
    let isManagementKey: Bool?
    let isProvisioningKey: Bool?
    let isFreeTier: Bool?
    let expiresAt: String?

    private enum CodingKeys: String, CodingKey {
        case label
        case isManagementKey = "is_management_key"
        case isProvisioningKey = "is_provisioning_key"
        case isFreeTier = "is_free_tier"
        case expiresAt = "expires_at"
    }

    /// Older accounts report the same capability under the legacy provisioning flag.
    var hasManagementCapability: Bool {
        isManagementKey ?? isProvisioningKey ?? false
    }
}

/// `GET /keys`
nonisolated struct APIKeyDTO: Decodable, Sendable {
    let hash: String
    let name: String?
    let label: String?
    let disabled: Bool?
    let limit: Decimal?
    let limitRemaining: Decimal?
    let limitReset: String?
    let includeBYOKInLimit: Bool?
    let usage: Decimal?
    let usageDaily: Decimal?
    let usageWeekly: Decimal?
    let usageMonthly: Decimal?
    let byokUsage: Decimal?
    let byokUsageDaily: Decimal?
    let byokUsageWeekly: Decimal?
    let byokUsageMonthly: Decimal?

    private enum CodingKeys: String, CodingKey {
        case hash, name, label, disabled, limit, usage
        case limitRemaining = "limit_remaining"
        case limitReset = "limit_reset"
        case includeBYOKInLimit = "include_byok_in_limit"
        case usageDaily = "usage_daily"
        case usageWeekly = "usage_weekly"
        case usageMonthly = "usage_monthly"
        case byokUsage = "byok_usage"
        case byokUsageDaily = "byok_usage_daily"
        case byokUsageWeekly = "byok_usage_weekly"
        case byokUsageMonthly = "byok_usage_monthly"
    }

    var resetInterval: ResetInterval? {
        guard let limitReset else { return nil }
        return ResetInterval(rawValue: limitReset.lowercased())
    }

    /// Credit spend inside the given window. `nil` interval means the lifetime total.
    func usage(in interval: ResetInterval?) -> Decimal {
        switch interval {
        case .daily: usageDaily ?? 0
        case .weekly: usageWeekly ?? 0
        case .monthly: usageMonthly ?? 0
        case nil: usage ?? 0
        }
    }

    /// BYOK spend inside the given window, counted only when the budget opts in.
    func byokUsage(in interval: ResetInterval?) -> Decimal {
        switch interval {
        case .daily: byokUsageDaily ?? 0
        case .weekly: byokUsageWeekly ?? 0
        case .monthly: byokUsageMonthly ?? 0
        case nil: byokUsage ?? 0
        }
    }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        if let label, !label.isEmpty { return label }
        return String(localized: "Unnamed key")
    }
}

/// `GET /guardrails`
nonisolated struct GuardrailDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let description: String?
    let workspaceID: String?
    let limitUSD: Decimal?
    let resetInterval: String?
    let includeBYOKInBudgets: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, description
        case workspaceID = "workspace_id"
        case limitUSD = "limit_usd"
        case resetInterval = "reset_interval"
        case includeBYOKInBudgets = "include_byok_in_budgets"
    }

    var interval: ResetInterval? {
        guard let resetInterval else { return nil }
        return ResetInterval(rawValue: resetInterval.lowercased())
    }

    /// Workspace defaults are named `Workspace <uuid> Default`, which is unreadable in
    /// a menu. Relabel them; keep author-chosen names untouched.
    var displayName: String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "Untitled guardrail")
        }
        if name.hasPrefix("Workspace "), name.hasSuffix(" Default") {
            return String(localized: "Workspace default")
        }
        return name
    }
}

/// `GET /guardrails/assignments/keys` — the whole join table in one call.
nonisolated struct GuardrailKeyAssignmentDTO: Decodable, Sendable {
    let id: String?
    let keyHash: String
    let guardrailID: String
    let keyName: String?
    let keyLabel: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case keyHash = "key_hash"
        case guardrailID = "guardrail_id"
        case keyName = "key_name"
        case keyLabel = "key_label"
    }
}

/// `GET /activity` — one row per (day, model, endpoint) for the last 30 **completed**
/// UTC days. Verified against a live account: today is absent, and `date` arrives as
/// `"2026-07-27 00:00:00"` rather than the documented `YYYY-MM-DD`. Only `usage` is
/// decoded, so the date-format discrepancy cannot bite us.
nonisolated struct ActivityRowDTO: Decodable, Sendable {
    let usage: Decimal?
    let byokUsageInference: Decimal?

    private enum CodingKeys: String, CodingKey {
        case usage
        case byokUsageInference = "byok_usage_inference"
    }
}

/// `POST /analytics/query` rows.
///
/// The endpoint returns numeric metrics inconsistently: `total_usage` arrives as a JSON
/// number while `tokens_total` and `request_count` arrive as strings. Verified against
/// a live account. `LenientNumber` accepts either so a format change on their side
/// cannot break decoding.
nonisolated struct AnalyticsRowDTO: Decodable, Sendable {
    let minute: String?
    /// Present instead of `minute` when the query used hourly granularity.
    let hour: String?
    let model: String?
    let totalUsage: LenientNumber?
    let tokensTotal: LenientNumber?
    let requestCount: LenientNumber?

    private enum CodingKeys: String, CodingKey {
        case minute = "date__minute"
        case hour = "date__hour"
        case model
        case totalUsage = "total_usage"
        case tokensTotal = "tokens_total"
        case requestCount = "request_count"
    }

    /// Buckets are UTC, e.g. `"2026-08-27 17:13:00"` — no timezone marker and not the
    /// ISO-8601 `T` form, so it needs its own parser.
    var bucket: Date? {
        guard let stamp = minute ?? hour else { return nil }
        return AnalyticsRowDTO.bucketFormatter.date(from: stamp)
    }

    private static let bucketFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// Decodes a JSON number or a numeric string into an exact `Decimal`.
nonisolated struct LenientNumber: Decodable, Sendable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
        } else if let string = try? container.decode(String.self), let decimal = Decimal(string: string) {
            value = decimal
        } else {
            value = 0
        }
    }

    var intValue: Int { NSDecimalNumber(decimal: value).intValue }
}

/// `{"data": {"data": [...], "metadata": {...}}}` — the payload is nested twice.
nonisolated struct AnalyticsEnvelope: Decodable, Sendable {
    let data: Inner

    nonisolated struct Inner: Decodable, Sendable {
        let data: [AnalyticsRowDTO]
        let metadata: Metadata?
    }

    nonisolated struct Metadata: Decodable, Sendable {
        let rowCount: Int?
        let truncated: Bool?

        private enum CodingKeys: String, CodingKey {
            case rowCount = "row_count"
            case truncated
        }
    }
}
