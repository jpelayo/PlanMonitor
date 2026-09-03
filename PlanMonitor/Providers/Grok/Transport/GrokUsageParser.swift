import Foundation

nonisolated enum GrokUsageParserError: Error, Equatable, LocalizedError {
    case missingConfig
    case noWeeklyUsage
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            String(localized: "Grok did not return a usage configuration.")
        case .noWeeklyUsage:
            String(localized: "Weekly SuperGrok usage is not available for this account.")
        case .invalidPayload(let reason):
            String(localized: "Grok changed its usage response: \(reason)")
        }
    }
}

nonisolated enum GrokUsageParser {
    static func parseWeeklyIfPresent(_ data: Data, fetchedAt: Date = Date(), planDisplayName: String? = nil) -> GrokUsageData? {
        try? parseWeekly(data, fetchedAt: fetchedAt, planDisplayName: planDisplayName)
    }

    static func parseWeekly(_ data: Data, fetchedAt: Date = Date(), planDisplayName: String? = nil) throws -> GrokUsageData {
        let response = try JSONDecoder().decode(GrokBillingResponseDTO.self, from: data)
        guard let config = response.config else {
            throw GrokUsageParserError.missingConfig
        }
        return try parseWeekly(config: config, fetchedAt: fetchedAt, planDisplayName: planDisplayName)
    }

    static func parseWeekly(
        config: GrokBillingConfigDTO,
        fetchedAt: Date = Date(),
        planDisplayName: String? = nil
    ) throws -> GrokUsageData {
        let period = config.currentPeriod
        let periodType = period?.type ?? ""
        guard periodType.uppercased().contains("WEEK") else {
            throw GrokUsageParserError.noWeeklyUsage
        }

        let start = parseDate(period?.start) ?? parseDate(config.billingPeriodStart)
        let end = parseDate(period?.end) ?? parseDate(config.billingPeriodEnd)
        if let start, let end, end <= start {
            throw GrokUsageParserError.invalidPayload("inverted weekly period")
        }

        let products = mappedProducts(config.productUsage)
        let percent: Double
        if let creditUsagePercent = config.creditUsagePercent, creditUsagePercent.isFinite {
            percent = clampPercent(creditUsagePercent)
        } else if !products.isEmpty {
            percent = clampPercent(products.reduce(0) { $0 + $1.utilization * 100 })
        } else {
            percent = 0
        }

        return GrokUsageData(
            weeklyUtilization: percent / 100,
            weeklyPeriodStart: start,
            weeklyResetsAt: end,
            products: products,
            prepaidBalance: config.prepaidBalance?.val,
            onDemandCap: config.onDemandCap?.val,
            onDemandUsed: config.onDemandUsed?.val,
            topUpMethod: config.topUpMethod,
            planDisplayName: planDisplayName,
            isUnifiedBilling: config.isUnifiedBillingUser ?? true,
            monthlyUsed: nil,
            monthlyLimit: nil,
            monthlyResetsAt: nil,
            fetchedAt: fetchedAt
        )
    }

    static func parseMonthly(_ data: Data, fetchedAt: Date = Date(), planDisplayName: String? = nil) throws -> GrokUsageData {
        let response = try JSONDecoder().decode(GrokBillingResponseDTO.self, from: data)
        guard let config = response.config else {
            throw GrokUsageParserError.missingConfig
        }
        return try parseMonthly(config: config, fetchedAt: fetchedAt, planDisplayName: planDisplayName)
    }

    static func parseMonthly(
        config: GrokBillingConfigDTO,
        fetchedAt: Date = Date(),
        planDisplayName: String? = nil
    ) throws -> GrokUsageData {
        guard let limit = config.monthlyLimit?.val, limit > 0 else {
            throw GrokUsageParserError.noWeeklyUsage
        }
        guard let used = config.used?.val else {
            throw GrokUsageParserError.invalidPayload("missing monthly used")
        }
        let start = parseDate(config.billingPeriodStart)
        let end = parseDate(config.billingPeriodEnd)
        if let start, let end, end <= start {
            throw GrokUsageParserError.invalidPayload("inverted monthly period")
        }

        return GrokUsageData(
            weeklyUtilization: nil,
            weeklyPeriodStart: start,
            weeklyResetsAt: nil,
            products: [],
            prepaidBalance: config.prepaidBalance?.val,
            onDemandCap: config.onDemandCap?.val,
            onDemandUsed: config.onDemandUsed?.val,
            topUpMethod: config.topUpMethod,
            planDisplayName: planDisplayName,
            isUnifiedBilling: config.isUnifiedBillingUser ?? false,
            monthlyUsed: max(0, used),
            monthlyLimit: limit,
            monthlyResetsAt: end,
            fetchedAt: fetchedAt
        )
    }

    static func parsePlanDisplayName(_ data: Data) -> String? {
        let response = try? JSONDecoder().decode(GrokSettingsResponseDTO.self, from: data)
        let name = response?.subscription_tier_display?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
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

    private static func mappedProducts(_ items: [GrokProductUsageDTO]?) -> [GrokProductUsage] {
        (items ?? []).compactMap { item in
            let name = item.product?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let percent = item.usagePercent ?? 0
            guard percent.isFinite else { return nil }
            return GrokProductUsage(product: name, utilization: clampPercent(percent) / 100)
        }
    }

    private static func clampPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}
