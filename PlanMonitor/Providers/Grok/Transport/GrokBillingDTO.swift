import Foundation

nonisolated struct GrokAmountDTO: Decodable, Sendable {
    var val: Double

    init(val: Double) {
        self.val = val
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Double.self, forKey: .val) {
            val = value
        } else if let value = try? container.decode(Int.self, forKey: .val) {
            val = Double(value)
        } else if let value = try? container.decode(String.self, forKey: .val),
                  let parsed = Double(value) {
            val = parsed
        } else {
            val = 0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case val
    }
}

nonisolated struct GrokPeriodDTO: Decodable, Sendable {
    var type: String?
    var start: String?
    var end: String?
}

nonisolated struct GrokProductUsageDTO: Decodable, Sendable {
    var product: String?
    var usagePercent: Double?
}

nonisolated struct GrokBillingConfigDTO: Decodable, Sendable {
    var currentPeriod: GrokPeriodDTO?
    var creditUsagePercent: Double?
    var productUsage: [GrokProductUsageDTO]?
    var onDemandCap: GrokAmountDTO?
    var onDemandUsed: GrokAmountDTO?
    var prepaidBalance: GrokAmountDTO?
    var topUpMethod: String?
    var isUnifiedBillingUser: Bool?
    var billingPeriodStart: String?
    var billingPeriodEnd: String?
    var monthlyLimit: GrokAmountDTO?
    var used: GrokAmountDTO?
}

nonisolated struct GrokBillingResponseDTO: Decodable, Sendable {
    var config: GrokBillingConfigDTO?
}

nonisolated struct GrokSettingsResponseDTO: Decodable, Sendable {
    var subscription_tier_display: String?
}

nonisolated struct OAuthTokenResponseDTO: Decodable, Sendable {
    var access_token: String?
    var refresh_token: String?
    var token_type: String?
    var expires_in: Double?
    var interval: Double?
    var scope: String?
    var device_code: String?
    var user_code: String?
    var verification_uri: String?
    var verification_uri_complete: String?
    var error: String?
    var error_description: String?
}
