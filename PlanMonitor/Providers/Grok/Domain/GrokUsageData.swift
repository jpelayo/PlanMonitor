import Foundation

nonisolated struct GrokProductUsage: Codable, Equatable, Sendable, Identifiable {
    var product: String
    var utilization: Double

    var id: String { product }

    var displayName: String {
        switch product {
        case "GrokBuild": String(localized: "Grok Build")
        case "GrokChat": String(localized: "Chat")
        case "Api": String(localized: "API")
        case "Imagine": String(localized: "Imagine")
        case "Voice": String(localized: "Voice")
        default: Self.humanize(product)
        }
    }

    private static func humanize(_ slug: String) -> String {
        let spaced = slug.unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append(" ")
            }
            result.append(String(scalar))
        }
        return spaced.replacing("Grok ", with: "")
    }
}

nonisolated struct GrokUsageData: Codable, Equatable, Sendable {
    var weeklyUtilization: Double?
    var weeklyPeriodStart: Date?
    var weeklyResetsAt: Date?
    var products: [GrokProductUsage]
    var prepaidBalance: Double?
    var onDemandCap: Double?
    var onDemandUsed: Double?
    var topUpMethod: String?
    var planDisplayName: String?
    var isUnifiedBilling: Bool
    var monthlyUsed: Double?
    var monthlyLimit: Double?
    var monthlyResetsAt: Date?
    var fetchedAt: Date

    static let empty = GrokUsageData(
        weeklyUtilization: nil,
        weeklyPeriodStart: nil,
        weeklyResetsAt: nil,
        products: [],
        prepaidBalance: nil,
        onDemandCap: nil,
        onDemandUsed: nil,
        topUpMethod: nil,
        planDisplayName: nil,
        isUnifiedBilling: false,
        monthlyUsed: nil,
        monthlyLimit: nil,
        monthlyResetsAt: nil,
        fetchedAt: .distantPast
    )

    var hasWeeklyUsage: Bool {
        weeklyUtilization != nil || weeklyResetsAt != nil
    }

    var usedPercent: Double? {
        weeklyUtilization.map { $0 * 100 }
    }

    var remainingPercent: Double? {
        usedPercent.map { max(0, 100 - $0) }
    }

    var sortedProducts: [GrokProductUsage] {
        products.sorted { $0.utilization > $1.utilization }
    }

    var hasExtraCredits: Bool {
        (prepaidBalance ?? 0) > 0 || (onDemandCap ?? 0) > 0
    }

    /// Whether Grok will recharge automatically — what its billing page calls "Recarga
    /// automática".
    ///
    /// This is an allowlist on purpose. The donor app excluded three known "off" values and
    /// treated everything else as on, which reported automatic recharge as active on an
    /// account whose page said it was not: the enum carries values beyond those three, and
    /// a method that merely records how credits *can* be bought is not automatic recharge.
    /// Anything that does not announce itself as automatic counts as off.
    var isAutoTopUpEnabled: Bool {
        guard let topUpMethod, !topUpMethod.isEmpty else { return false }
        return topUpMethod.uppercased().contains("AUTO")
    }
}
