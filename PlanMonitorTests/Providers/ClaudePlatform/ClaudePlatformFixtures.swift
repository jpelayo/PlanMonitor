import Foundation
@testable import PlanMonitor

/// The console responses captured from platform.claude.com on 2026-10-09, verbatim (plan §1.2).
/// They are the only real samples there are: the decoders and the money model are held to them,
/// not to a shape anyone remembered. The fifth capture, `link-state`, is not here because the app
/// no longer reads that codenamed path.
enum ClaudePlatformFixtures {
    static let organizationID = "37fd2a8d-46c7-4f8b-883c-54f91b4b524a"

    static let currentSpend = #"{"amount":46,"resets_at":"2026-11-01T00:00:00Z"}"#

    static let spendLimits = #"{"spend_limits":[{"id":"0579ae51-aedb-49b5-87b7-bb27a4374dcc","limit_usd":19500,"limit_action":"notify_only","type":"self_selected_spend_limit","triggered_until":null,"ignored_until":null},{"id":"ab4a40ac-eb97-407a-b776-da69e628423b","limit_usd":20000,"limit_action":"notify_and_pause","type":"self_selected_spend_limit","triggered_until":null,"ignored_until":null}],"enforced_limit_usd":50000}"#

    static let autoRecharge = #"{"status":"disabled","stripe_error_code":null,"target_amount":1500,"threshold_amount":500,"disabled_reason":null,"disabled_at":null}"#

    static let prepaidCredits = #"{"amount":19955,"currency":"USD","balance":{"money":null,"credits":{"amount_minor":19955,"exponent":2}},"balance_credits":199,"amount_without_scoped_credits":0,"auto_reload_settings":null,"auto_reload_disabled_reason":null,"auto_reload_stripe_error_code":null,"pending_invoice_amount_cents":null,"last_paid_purchase_cents":null,"expiry_policy_months":null,"credit_expiry_policy":null,"auto_reload_terms_banner":null,"tranches":[],"promo_tranches":[{"remaining_amount_minor_units":19954,"currency":"USD","expires_at":"2026-11-04T00:00:00Z","granted_amount_minor_units":20000,"granted_at":"2026-10-08T16:59:00.638000Z","remaining":{"money":null,"credits":{"amount_minor":19954,"exponent":2}},"granted":{"money":null,"credits":{"amount_minor":20000,"exponent":2}},"program_id":"subscription_api_credit","name":"API credit (Max 20x)","id":"0d2ae5b5-4ca0-4374-9a4e-3cc68cea40d6","scope":{"kind":"scoped","applies_to":[{"product":"agent_sdk","model_family":null,"model_version":null},{"product":"api","model_family":null,"model_version":null},{"product":"batch","model_family":null,"model_version":null},{"product":"console","model_family":null,"model_version":null},{"product":"managed-agents","model_family":null,"model_version":null},{"product":"managed-agents-onprem","model_family":null,"model_version":null}]}}],"next_expires_at":"2026-11-04T00:00:00Z"}"#

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ClaudePlatformBilling.decode(type, from: Data(json.utf8))
    }

    /// When the captures were taken. Assembly drops tranches already past their expiry, so every
    /// test assembles at this fixed moment: the captured grant expires 2026-11-04, and on the real
    /// clock the suite would start failing that day.
    static let capturedAt = date("2026-10-09T12:00:00Z")

    /// The captured account, assembled exactly as a poll assembles it.
    static func capturedSnapshot() throws -> ClaudePlatformSnapshot {
        ClaudePlatformBilling.assemble(
            credits: try decode(ClaudePlatformPrepaidCreditsResponse.self, prepaidCredits),
            spend: try decode(ClaudePlatformCurrentSpendResponse.self, currentSpend),
            limits: try decode(ClaudePlatformSpendLimitsResponse.self, spendLimits),
            autoRecharge: try decode(ClaudePlatformAutoRechargeResponse.self, autoRecharge),
            now: capturedAt
        )
    }

    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }
}
