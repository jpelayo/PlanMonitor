import Foundation

/// One row of `GET /api/v1/budgets/members` (docs, `console/api/budgets`):
///
///     {"user_id":"user_…","email":"…","limit_micro_cents":"7525000000","spent_micro_cents":"1250000000",
///      "exceeded":false,"resets_at":"2026-10-01T00:00:00.000Z","source":"custom","updated_at":"…"}
///
/// Money arrives as microcents in **decimal strings**; a plain JSON number is accepted too, so a
/// change of representation does not blank the provider. `limit_micro_cents` and `source` are
/// `null` for a member without a budget — unlimited, not zero.
nonisolated struct OpenCodeMemberBudgetDTO: Decodable, Sendable {
    let userID: String
    let email: String?
    let limitMicroCents: String?
    let spentMicroCents: String?
    let exceeded: Bool?
    let resetsAt: String?
    let source: String?

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case limitMicroCents = "limit_micro_cents"
        case spentMicroCents = "spent_micro_cents"
        case exceeded
        case resetsAt = "resets_at"
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        limitMicroCents = Self.decimalString(container, .limitMicroCents)
        spentMicroCents = Self.decimalString(container, .spentMicroCents)
        exceeded = try container.decodeIfPresent(Bool.self, forKey: .exceeded)
        resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    private static func decimalString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return string
        }
        if let number = try? container.decodeIfPresent(Decimal.self, forKey: key) {
            return NSDecimalNumber(decimal: number).stringValue
        }
        return nil
    }

    var member: OpenCodeMemberBudget {
        OpenCodeMemberBudget(
            userID: userID,
            email: email,
            spent: OpenCodeMoney.dollars(fromMicroCents: spentMicroCents),
            budget: OpenCodeMoney.dollars(fromMicroCents: limitMicroCents),
            exceeded: exceeded ?? false,
            resetsAt: resetsAt.flatMap(Self.date(from:)),
            source: source.flatMap(OpenCodeSnapshot.BudgetSource.init(rawValue:))
        )
    }

    /// `2026-11-01T00:00:00.000Z`, with or without the fractional seconds.
    static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
