import Foundation

// MARK: - Response shapes

// Every console response type carries the `ClaudePlatform` prefix. The Claude provider already
// declares `PrepaidCreditsResponse`, `BootstrapResponse` and friends for *claude.ai subscription*
// billing; the same names here would invite reading one org's counters with the other's model.
//
// Shapes as captured from platform.claude.com on 2026-10-09 (plan §1.2). Every field is optional:
// the console returns `null` for what does not apply to an account, and a missing figure must
// degrade its own row, never the whole poll.

/// `GET /api/organizations/{org}/prepaid/credits`
nonisolated struct ClaudePlatformPrepaidCreditsResponse: Decodable, Sendable {
    let amount: Int?
    let currency: String?
    let balance: Balance?
    /// Card-paid credit — everything that is not a scoped (promotional) grant.
    let amountWithoutScopedCredits: Int?
    let pendingInvoiceAmountCents: Int?
    let tranches: [Tranche]?
    let promoTranches: [Tranche]?
    let nextExpiresAt: String?

    nonisolated struct Balance: Decodable, Sendable {
        let credits: MinorAmount?
    }

    nonisolated struct MinorAmount: Decodable, Sendable {
        let amountMinor: Int?
        /// Decimal places between minor and major units — `2` for USD.
        let exponent: Int?
    }

    nonisolated struct Tranche: Decodable, Sendable {
        let remainingAmountMinorUnits: Int?
        let grantedAmountMinorUnits: Int?
        let currency: String?
        let expiresAt: String?
        let name: String?
        let remaining: Balance?
    }
}

/// `GET /api/organizations/{org}/current_spend`
nonisolated struct ClaudePlatformCurrentSpendResponse: Decodable, Sendable {
    let amount: Int?
    let resetsAt: String?
}

/// `GET /api/organizations/{org}/spend_limits`
///
/// `limit_usd` and `enforced_limit_usd` are **minor units** despite the suffix: the captured
/// account's limits are 19500 and 20000 against a $200 grant, coherent only as $195 and $200.
nonisolated struct ClaudePlatformSpendLimitsResponse: Decodable, Sendable {
    let spendLimits: [Limit]?
    let enforcedLimitUsd: Int?

    nonisolated struct Limit: Decodable, Sendable {
        let limitUsd: Int?
        let limitAction: String?
    }
}

/// `GET /api/organizations/{org}/prepaid/auto_recharge` — the source of truth for auto-payment.
/// `prepaid/credits`' own `auto_reload_settings` is `null` on a console account.
nonisolated struct ClaudePlatformAutoRechargeResponse: Decodable, Sendable {
    let status: String?
    let targetAmount: Int?
    let thresholdAmount: Int?
}

// Not read: `/api/quirky-lollipop/organizations/{org}/link-state`. It names the linked claude.ai
// plan, but its path is an internal codename, so nothing shown may depend on it (user decision,
// 2026-10-14).

// MARK: - Assembly

/// Pure functions from the console's responses to `ClaudePlatformSnapshot`, kept apart from the
/// client so the fixtures in `ClaudePlatformBillingTests` exercise exactly what ships.
nonisolated enum ClaudePlatformBilling {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }

    static func assemble(
        credits: ClaudePlatformPrepaidCreditsResponse?,
        spend: ClaudePlatformCurrentSpendResponse?,
        limits: ClaudePlatformSpendLimitsResponse?,
        autoRecharge: ClaudePlatformAutoRechargeResponse?
    ) -> ClaudePlatformSnapshot {
        let promo = promoSummary(credits?.promoTranches)
        // The account's own currency, else the one its grants name — never an assumed USD. With
        // neither, amounts are shown bare.
        let currency = normalizedCurrency(credits?.currency) ?? promo.currencies.sorted().first
        let exponent = credits?.balance?.credits?.exponent
            ?? credits?.promoTranches?.lazy.compactMap({ $0.remaining?.credits?.exponent }).first
            ?? ClaudePlatformMoney.defaultExponent

        let mismatch = currency.map { currency in promo.currencies.contains { $0 != currency } } ?? false

        return ClaudePlatformSnapshot(
            currency: currency,
            exponent: exponent,
            promoGranted: promo.granted,
            promoRemaining: ClaudePlatformMoney.normalizedBalance(promo.remaining),
            promoExpiresAt: promo.earliestExpiry ?? credits?.nextExpiresAt.flatMap(parseDate),
            promoName: promo.name,
            prepaidRemaining: ClaudePlatformMoney.normalizedBalance(credits?.amountWithoutScopedCredits),
            pendingInvoice: ClaudePlatformMoney.normalizedBalance(credits?.pendingInvoiceAmountCents),
            spendUsed: spend?.amount.map { max(0, $0) },
            spendResetsAt: spend?.resetsAt.flatMap(parseDate),
            enforcedSpendLimit: limits?.enforcedLimitUsd.flatMap { $0 > 0 ? $0 : nil },
            selfSelectedLimits: selfSelectedLimits(limits),
            autoRecharge: autoRechargeState(autoRecharge),
            currencyMismatch: mismatch
        )
    }

    // MARK: Pieces

    private struct PromoSummary {
        var granted: Int?
        var remaining: Int?
        var earliestExpiry: Date?
        var name: String?
        var currencies: Set<String> = []
    }

    /// Summed across tranches, as `ClaudeUsagePollingService.creditSummary` does, and never mixed
    /// with the independent spend counter. A tranche with no grant is not credit.
    private static func promoSummary(_ tranches: [ClaudePlatformPrepaidCreditsResponse.Tranche]?) -> PromoSummary {
        var summary = PromoSummary()
        let valid = (tranches ?? []).filter { ($0.grantedAmountMinorUnits ?? 0) > 0 }
        guard !valid.isEmpty else { return summary }

        var granted = 0
        var remaining = 0
        for tranche in valid {
            let trancheGranted = tranche.grantedAmountMinorUnits ?? 0
            let trancheRemaining = tranche.remainingAmountMinorUnits
                ?? tranche.remaining?.credits?.amountMinor
                ?? 0
            granted += trancheGranted
            remaining += min(max(0, trancheRemaining), trancheGranted)
            if let currency = normalizedCurrency(tranche.currency) {
                summary.currencies.insert(currency)
            }
        }
        summary.granted = granted
        summary.remaining = remaining
        summary.earliestExpiry = valid.compactMap { $0.expiresAt.flatMap(parseDate) }.min()
        summary.name = valid.lazy.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return summary
    }

    private static func selfSelectedLimits(_ response: ClaudePlatformSpendLimitsResponse?) -> [ClaudePlatformSnapshot.SpendLimit] {
        (response?.spendLimits ?? [])
            .compactMap { limit -> ClaudePlatformSnapshot.SpendLimit? in
                guard let amount = limit.limitUsd, amount > 0 else { return nil }
                let action = limit.limitAction
                    .flatMap(ClaudePlatformSnapshot.SpendLimit.Action.init(rawValue:)) ?? .unknown
                return ClaudePlatformSnapshot.SpendLimit(amount: amount, action: action)
            }
            .sorted { $0.amount < $1.amount }
    }

    /// Only a status the app recognises becomes a state: an unknown one is reported as unknown
    /// (`nil`), never guessed as off — the Grok demo bug was exactly a guess like that.
    private static func autoRechargeState(_ response: ClaudePlatformAutoRechargeResponse?) -> ClaudePlatformSnapshot.AutoRecharge? {
        guard let status = response?.status?.lowercased() else { return nil }
        let isEnabled: Bool
        switch status {
        case "disabled", "off", "inactive": isEnabled = false
        case "enabled", "on", "active": isEnabled = true
        default: return nil
        }
        return ClaudePlatformSnapshot.AutoRecharge(
            isEnabled: isEnabled,
            targetAmount: response?.targetAmount,
            thresholdAmount: response?.thresholdAmount
        )
    }

    private static func normalizedCurrency(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Identity

nonisolated struct ClaudePlatformOrganization: Sendable, Equatable {
    let id: String
    let name: String?
    let capabilities: [String]
}

nonisolated struct ClaudePlatformIdentity: Sendable, Equatable {
    let email: String?
    let organizations: [ClaudePlatformOrganization]

    /// The console org to read billing for: one with the `api` capability when the list says, the
    /// first otherwise. **Unverified against a signed-in response** (plan §5.4) — the first real
    /// sign-in is where this gets confirmed.
    var preferredOrganization: ClaudePlatformOrganization? {
        organizations.first { $0.capabilities.contains { $0.lowercased() == "api" } }
            ?? organizations.first
    }
}

/// Reads identity out of `/api/bootstrap` and `/api/organizations` with `JSONSerialization`
/// rather than a fixed type: the signed-in shape has not been captured yet, so this accepts the
/// field names the claude.ai side of the same backend uses and ignores the rest.
nonisolated enum ClaudePlatformIdentityParser {
    enum BootstrapOutcome: Equatable {
        /// `"account": null` — measured as the unauthenticated answer, at HTTP 200.
        case signedOut
        case identity(ClaudePlatformIdentity)
        /// Not the shape we know. Transient by the house rule: a 200 with an unexpected body
        /// never signs anyone out.
        case malformed
    }

    static func parseBootstrap(_ json: Any) -> BootstrapOutcome {
        guard let object = json as? [String: Any], let account = object["account"] else { return .malformed }
        if account is NSNull { return .signedOut }
        guard let account = account as? [String: Any] else { return .malformed }

        let email = (account["email_address"] as? String) ?? (account["email"] as? String)
        let memberships = account["memberships"] as? [[String: Any]] ?? []
        let organizations = memberships.compactMap { membership in
            (membership["organization"] as? [String: Any]).flatMap(organization(from:))
        }
        return .identity(ClaudePlatformIdentity(email: email, organizations: organizations))
    }

    static func parseOrganizations(_ json: Any) -> [ClaudePlatformOrganization] {
        (json as? [[String: Any]] ?? []).compactMap(organization(from:))
    }

    private static func organization(from object: [String: Any]) -> ClaudePlatformOrganization? {
        guard let id = (object["uuid"] as? String) ?? (object["id"] as? String), !id.isEmpty else { return nil }
        return ClaudePlatformOrganization(
            id: id,
            name: object["name"] as? String,
            capabilities: object["capabilities"] as? [String] ?? []
        )
    }
}
