//
//  ClaudeUsagePollingService.swift
//  PlanTracker
//

import Foundation

actor ClaudeUsagePollingService {
    private enum PollingError: Error {
        case organizationUnavailable
    }

    private struct OrganizationContext: Sendable {
        let orgUuid: String
        let planTier: ClaudePlanTier
        let planDisplayNameOverride: String?
        let refreshedAt: Date
    }

    private struct BillingSnapshot: Sendable {
        let prepaidCreditsRemaining: Int?
        let prepaidCreditsTotal: Int?
        let prepaidCreditsCurrency: String?
        let prepaidCreditsArePromotional: Bool?
        let prepaidAutoReloadEnabled: Bool?
        let paidCreditsRemaining: Int?
        let paidCreditsTotal: Int?
        let paidCreditsCurrency: String?
        let pendingInvoiceAmount: Int?
        let overageMonthlyLimit: Int?
        let overageUsedCredits: Int?
        let overageCurrency: String?
        let overageEnabled: Bool?
        let overageOutOfCredits: Bool?
        let refreshedAt: Date
    }

    private let apiClient: ClaudeAPIClient
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 300
    private var organizationContext: OrganizationContext?
    private var billingSnapshot: BillingSnapshot?
    private var organizationRefreshInterval: TimeInterval = 6 * 3600
    private var billingRefreshInterval: TimeInterval = 3600

    private var onUsageUpdate: (@Sendable (ClaudeUsageData) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?
    private var onSchedule: (@Sendable (Date?) -> Void)?
    private var cycleGeneration = 0
    private var nextFireAt: Date? {
        didSet { onSchedule?(nextFireAt) }
    }

    init(apiClient: ClaudeAPIClient) {
        self.apiClient = apiClient
    }

    func setCallbacks(
        onUsageUpdate: @escaping @Sendable (ClaudeUsageData) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        onSchedule: (@Sendable (Date?) -> Void)? = nil
    ) {
        self.onUsageUpdate = onUsageUpdate
        self.onError = onError
        self.onSchedule = onSchedule
    }

    /// Applies at once by interrupting the pending sleep; never forces a fetch. The pending
    /// cycle restarts from now, so the published deadline is always a full interval out.
    func setPollingInterval(_ interval: TimeInterval) {
        let clamped = Swift.max(60, interval)
        guard clamped != pollingInterval else { return }
        pollingInterval = clamped
        cycleGeneration &+= 1
    }

    /// Restarts the pending cycle from now without fetching. The manual Refresh button has
    /// just done this cycle's work out of band, so the next automatic poll — and the
    /// countdown built from its deadline — should be a full interval away.
    func restartCycle() {
        cycleGeneration &+= 1
    }

    func startPolling() {
        stopPolling()

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchUsage()
                await self.sleepUntilNextCycle()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        nextFireAt = nil
    }

    /// Sleeps in one-second slices so an interval change reschedules immediately and the
    /// published deadline is the real one.
    private func sleepUntilNextCycle() async {
        var generation = cycleGeneration
        var deadline = Date().addingTimeInterval(pollingInterval)
        nextFireAt = deadline
        defer { nextFireAt = nil }
        while !Task.isCancelled {
            if cycleGeneration != generation {
                // Interval change or manual refresh: restart the cycle from now, no fetch.
                // Re-anchoring on the cycle's original start instead would leave the
                // countdown short by however much of the cycle had already run.
                generation = cycleGeneration
                deadline = Date().addingTimeInterval(pollingInterval)
                nextFireAt = deadline
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return }
            try? await Task.sleep(for: .seconds(min(remaining, 1.0)))
        }
    }

    func resetSteadyState() {
        organizationContext = nil
        billingSnapshot = nil
        billingRefreshInterval = 3600
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) {
        switch level {
        case .warning:
            billingRefreshInterval = max(billingRefreshInterval, 2 * 3600)
        case .critical:
            billingRefreshInterval = max(billingRefreshInterval, 6 * 3600)
        }
    }

    func fetchUsage(forceMetadataRefresh: Bool = false) async {
        do {
            let usageData = try await fetchUsageData(forceMetadataRefresh: forceMetadataRefresh)
            onUsageUpdate?(usageData)
        } catch {
            onError?(error)
        }
    }

    private func fetchUsageData(forceMetadataRefresh: Bool) async throws -> ClaudeUsageData {
        let organization = try await resolveOrganizationContext(forceRefresh: forceMetadataRefresh)
        let usage = try await apiClient.fetchUsage(orgUuid: organization.orgUuid)
        let billing = try await resolveBillingSnapshot(
            orgUuid: organization.orgUuid,
            forceRefresh: forceMetadataRefresh
        )

        let fiveHourReset = usage.fiveHour?.resetsAt.flatMap(parseDate)
        let sevenDayReset = usage.sevenDay?.resetsAt.flatMap(parseDate)
        let sevenDayOpusReset = usage.sevenDayOpus?.resetsAt.flatMap(parseDate)
        let sevenDaySonnetReset = usage.sevenDaySonnet?.resetsAt.flatMap(parseDate)
        let sevenDayScopedReset = usage.sevenDayScoped?.period.resetsAt.flatMap(parseDate)
        let extraUsageReset = usage.extraUsage?.resetsAt.flatMap(parseDate)

        let usageReportsExtraSpendDisabled = usage.spend?.enabled == false || usage.extraUsageEnabled == false
        let spendLimit: Int?
        let spendUsed: Int?
        let spendCurrency: String?
        let spendEnabled: Bool?

        if let spend = usage.spend {
            spendLimit = usageReportsExtraSpendDisabled ? nil : (spend.limit?.amountMinor ?? spend.cap?.credits?.amountMinor)
            spendUsed = spend.used?.amountMinor
            spendCurrency = spend.used?.currency
                ?? spend.limit?.currency
                ?? spend.balance?.currency
            spendEnabled = spend.enabled ?? usage.extraUsageEnabled
        } else if usageReportsExtraSpendDisabled {
            spendLimit = nil
            spendUsed = nil
            spendCurrency = nil
            spendEnabled = false
        } else {
            spendLimit = billing?.overageMonthlyLimit
            spendUsed = billing?.overageUsedCredits
            spendCurrency = billing?.overageCurrency
            spendEnabled = usage.extraUsageEnabled ?? billing?.overageEnabled
        }
        let spendOutOfCredits = billing?.overageOutOfCredits

        let prepaidRemaining: Int?
        let prepaidTotal: Int?
        let prepaidCurrency: String?
        let prepaidArePromotional: Bool?
        if let spend = usage.spend {
            // `/usage` may include `spend` while omitting its balance. Keep the
            // dedicated prepaid endpoint as a fallback so untouched free credit
            // still renders as a 0% gauge.
            let usageBalance = Self.normalizedPrepaidCreditsRemaining(spend.balance?.amountMinor)
            let billingBalance = Self.normalizedPrepaidCreditsRemaining(billing?.prepaidCreditsRemaining)
            let hasPromotionalBillingBalance = billing?.prepaidCreditsArePromotional == true
                && Self.hasDisplayablePrepaidCredits(billingBalance)
            let prefersUsageBalance = !hasPromotionalBillingBalance
                && Self.hasDisplayablePrepaidCredits(usageBalance)
            let resolvedBalance = prefersUsageBalance ? usageBalance : billingBalance

            prepaidRemaining = resolvedBalance
            prepaidTotal = Self.hasDisplayablePrepaidCredits(resolvedBalance) ? billing?.prepaidCreditsTotal : nil
            prepaidCurrency = Self.hasDisplayablePrepaidCredits(resolvedBalance)
                ? (prefersUsageBalance
                    ? (spend.balance?.currency ?? billing?.prepaidCreditsCurrency ?? spendCurrency)
                    : billing?.prepaidCreditsCurrency)
                : nil
            prepaidArePromotional = Self.hasDisplayablePrepaidCredits(resolvedBalance)
                ? billing?.prepaidCreditsArePromotional
                : nil
        } else {
            let normalizedBalance = Self.normalizedPrepaidCreditsRemaining(billing?.prepaidCreditsRemaining)
            prepaidRemaining = normalizedBalance
            prepaidTotal = Self.hasDisplayablePrepaidCredits(normalizedBalance) ? billing?.prepaidCreditsTotal : nil
            prepaidCurrency = Self.hasDisplayablePrepaidCredits(normalizedBalance) ? billing?.prepaidCreditsCurrency : nil
            prepaidArePromotional = Self.hasDisplayablePrepaidCredits(normalizedBalance)
                ? billing?.prepaidCreditsArePromotional
                : nil
        }

        let hasMonetaryOverage = {
            guard let monthlyLimit = spendLimit,
                  let usedCredits = spendUsed,
                  let currency = spendCurrency else {
                return false
            }
            return !usageReportsExtraSpendDisabled && monthlyLimit > 0 && usedCredits >= 0 && !currency.isEmpty
        }()

        let canonicalExtraUsageUtilization = hasMonetaryOverage ? nil : usage.extraUsage?.utilization
        let canonicalExtraUsageReset = hasMonetaryOverage ? nil : extraUsageReset
        let canonicalOverageEnabled: Bool? = spendEnabled ?? (hasMonetaryOverage ? true : billing?.overageEnabled)

        return ClaudeUsageData(
            fiveHourUtilization: usage.fiveHour?.utilization,
            fiveHourResetsAt: fiveHourReset,
            sevenDayUtilization: usage.sevenDay?.utilization,
            sevenDayResetsAt: sevenDayReset,
            sevenDayOpusUtilization: usage.sevenDayOpus?.utilization,
            sevenDayOpusResetsAt: sevenDayOpusReset,
            sevenDaySonnetUtilization: usage.sevenDaySonnet?.utilization,
            sevenDaySonnetResetsAt: sevenDaySonnetReset,
            sevenDayScopedLabel: usage.sevenDayScoped?.label,
            sevenDayScopedUtilization: usage.sevenDayScoped?.period.utilization,
            sevenDayScopedResetsAt: sevenDayScopedReset,
            extraUsageUtilization: canonicalExtraUsageUtilization,
            extraUsageResetsAt: canonicalExtraUsageReset,
            planTier: organization.planTier,
            planDisplayNameOverride: organization.planDisplayNameOverride,
            prepaidCreditsRemaining: prepaidRemaining,
            prepaidCreditsTotal: prepaidTotal,
            prepaidCreditsCurrency: prepaidCurrency,
            prepaidCreditsArePromotional: prepaidArePromotional,
            prepaidAutoReloadEnabled: billing?.prepaidAutoReloadEnabled,
            paidCreditsRemaining: billing?.paidCreditsRemaining,
            paidCreditsTotal: billing?.paidCreditsTotal,
            paidCreditsCurrency: billing?.paidCreditsCurrency,
            pendingInvoiceAmount: billing?.pendingInvoiceAmount,
            overageMonthlyLimit: spendLimit,
            overageUsedCredits: spendUsed,
            overageCurrency: spendCurrency,
            overageEnabled: canonicalOverageEnabled,
            overageOutOfCredits: spendOutOfCredits
        )
    }

    private func resolveOrganizationContext(forceRefresh: Bool) async throws -> OrganizationContext {
        if !forceRefresh,
           let organizationContext,
           Date().timeIntervalSince(organizationContext.refreshedAt) < organizationRefreshInterval {
            return organizationContext
        }

        do {
            let organizations = try await apiClient.fetchOrganizations()
            guard let org = organizations.first, let orgUuid = org.uuid, !orgUuid.isEmpty else {
                if let organizationContext {
                    return organizationContext
                }
                throw PollingError.organizationUnavailable
            }

            let resolvedPlanTier = determinePlanTier(from: [org])
            let planDisplayNameOverride = determinePlanDisplayNameOverride(
                planTier: resolvedPlanTier,
                rateLimitTier: org.rateLimitTier
            )

            let resolved = OrganizationContext(
                orgUuid: orgUuid,
                planTier: resolvedPlanTier,
                planDisplayNameOverride: planDisplayNameOverride,
                refreshedAt: Date()
            )
            organizationContext = resolved
            return resolved
        } catch {
            if let organizationContext {
                return organizationContext
            }
            throw error
        }
    }

    private func resolveBillingSnapshot(orgUuid: String, forceRefresh: Bool) async throws -> BillingSnapshot? {
        if !forceRefresh,
           let billingSnapshot,
           Date().timeIntervalSince(billingSnapshot.refreshedAt) < billingRefreshInterval {
            return billingSnapshot
        }

        do {
            let prepaidCredits = try await apiClient.fetchPrepaidCredits(orgUuid: orgUuid)
            let creditGrant = try await apiClient.fetchOverageCreditGrant(orgUuid: orgUuid)
            let overageSpendLimit = try await apiClient.fetchOverageSpendLimit(orgUuid: orgUuid)

            var prepaidRemaining: Int?
            var prepaidTotal: Int?
            var prepaidCurrency: String?
            var prepaidArePromotional: Bool?
            var paidRemaining: Int?
            var paidTotal: Int?
            var paidCurrency: String?
            var pendingInvoiceAmount: Int?
            var autoReloadEnabled: Bool?
            if let prepaidCredits {
                autoReloadEnabled = prepaidCredits.autoReloadSettings?.enabled ?? false
                pendingInvoiceAmount = Self.normalizedPrepaidCreditsRemaining(
                    prepaidCredits.pendingInvoiceAmountCents
                )

                if let promotionalCredits = Self.promotionalCredits(from: prepaidCredits) {
                    // Promo tranches identify their own grant and balance. Do not
                    // mix the independent `spend.used` counter into this bucket.
                    prepaidRemaining = Self.normalizedPrepaidCreditsRemaining(promotionalCredits.remaining)
                    prepaidTotal = promotionalCredits.granted
                    prepaidCurrency = promotionalCredits.currency
                    prepaidArePromotional = true
                    paidRemaining = Self.normalizedPrepaidCreditsRemaining(
                        max(0, prepaidCredits.amount - promotionalCredits.remaining)
                    )
                    paidCurrency = prepaidCredits.currency
                    if let paidCredits = Self.creditSummary(from: prepaidCredits.tranches) {
                        paidRemaining = Self.normalizedPrepaidCreditsRemaining(paidCredits.remaining)
                        paidTotal = paidCredits.granted
                        paidCurrency = paidCredits.currency
                    } else {
                        paidTotal = paidRemaining
                    }
                } else {
                    paidRemaining = Self.normalizedPrepaidCreditsRemaining(prepaidCredits.amount)
                    paidCurrency = prepaidCredits.currency
                    paidTotal = Self.creditSummary(from: prepaidCredits.tranches)?.granted
                        ?? (creditGrant?.granted == true ? creditGrant?.amountMinorUnits : paidRemaining)
                }
            }

            if !Self.hasDisplayablePrepaidCredits(prepaidRemaining) {
                prepaidTotal = nil
                prepaidCurrency = nil
            }

            let resolved = BillingSnapshot(
                prepaidCreditsRemaining: prepaidRemaining,
                prepaidCreditsTotal: prepaidTotal,
                prepaidCreditsCurrency: prepaidCurrency,
                prepaidCreditsArePromotional: prepaidArePromotional,
                prepaidAutoReloadEnabled: autoReloadEnabled,
                paidCreditsRemaining: paidRemaining,
                paidCreditsTotal: paidTotal,
                paidCreditsCurrency: paidCurrency,
                pendingInvoiceAmount: pendingInvoiceAmount,
                overageMonthlyLimit: overageSpendLimit?.monthlyCreditLimit,
                overageUsedCredits: overageSpendLimit?.usedCredits,
                overageCurrency: overageSpendLimit?.currency,
                overageEnabled: overageSpendLimit?.isEnabled,
                overageOutOfCredits: overageSpendLimit?.outOfCredits,
                refreshedAt: Date()
            )
            billingSnapshot = resolved
            return resolved
        } catch {
            if let billingSnapshot {
                return billingSnapshot
            }
            throw error
        }
    }

    private static func promotionalCredits(
        from response: PrepaidCreditsResponse
    ) -> (remaining: Int, granted: Int, currency: String)? {
        creditSummary(from: response.promoTranches)
    }

    private static func creditSummary(
        from tranches: [PrepaidCreditsResponse.CreditTranche]?
    ) -> (remaining: Int, granted: Int, currency: String)? {
        guard let tranches else { return nil }

        let validTranches = tranches.filter {
            $0.grantedAmountMinorUnits > 0
                && $0.remainingAmountMinorUnits >= 0
                && !$0.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let first = validTranches.first else { return nil }

        let currency = first.currency.uppercased()
        guard validTranches.allSatisfy({ $0.currency.uppercased() == currency }) else {
            return nil
        }

        let granted = validTranches.reduce(0) { $0 + $1.grantedAmountMinorUnits }
        let remaining = validTranches.reduce(0) {
            $0 + min($1.remainingAmountMinorUnits, $1.grantedAmountMinorUnits)
        }
        guard granted > 0 else { return nil }

        return (remaining: remaining, granted: granted, currency: currency)
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func determinePlanTier(from organizations: [Organization]?) -> ClaudePlanTier {
        guard let org = organizations?.first else {
            return .unknown
        }

        if let tier = org.rateLimitTier?.lowercased() {
            if tier.contains("max") { return .max }
            if tier.contains("pro") { return .pro }
            if tier.contains("team") { return .team }
            if tier.contains("enterprise") { return .enterprise }
            if tier.contains("free") { return .free }
        }

        if let capabilities = org.capabilities {
            if capabilities.contains(where: { $0.lowercased().contains("max") }) {
                return .max
            } else if capabilities.contains(where: { $0.lowercased().contains("pro") }) {
                return .pro
            }
        }

        return .unknown
    }

    private func determinePlanDisplayNameOverride(
        planTier: ClaudePlanTier,
        rateLimitTier: String?
    ) -> String? {
        guard planTier == .max,
              let multiplier = extractRateLimitMultiplier(from: rateLimitTier) else {
            return nil
        }
        return "Max (\(multiplier))"
    }

    private func extractRateLimitMultiplier(from rateLimitTier: String?) -> String? {
        guard let rawTier = rateLimitTier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !rawTier.isEmpty,
              rawTier.contains("max") else {
            return nil
        }

        // Strict primary form (ex: default_claude_max_20x).
        if let multiplier = extractMultiplier(
            in: rawTier,
            pattern: #"^default_[a-z0-9_]*max_([1-9][0-9]{0,2})x$"#
        ) {
            return multiplier
        }

        // Narrow fallback with separators to avoid accidental matches.
        return extractMultiplier(
            in: rawTier,
            pattern: #"(?:^|_)max_([1-9][0-9]{0,2})x(?:_|$)"#
        )
    }

    private func extractMultiplier(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let digits = String(text[captureRange])
        guard let value = Int(digits), (1...500).contains(value) else {
            return nil
        }
        return "\(value)x"
    }

    private static func normalizedPrepaidCreditsRemaining(_ amount: Int?) -> Int? {
        guard let amount else { return nil }
        let normalized = max(0, amount)
        return normalized <= ClaudeUsageData.cosmeticPrepaidResidueThresholdMinorUnits ? 0 : normalized
    }

    private static func hasDisplayablePrepaidCredits(_ amount: Int?) -> Bool {
        guard let amount else { return false }
        return amount > ClaudeUsageData.cosmeticPrepaidResidueThresholdMinorUnits
    }
}
