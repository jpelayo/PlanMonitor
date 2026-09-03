import Foundation

nonisolated enum DemoGrokUsage {
    static func snapshot(now: Date = Date()) -> GrokUsageData {
        GrokUsageData(
            weeklyUtilization: 0.42,
            weeklyPeriodStart: now.addingTimeInterval(-3 * 24 * 3600),
            weeklyResetsAt: now.addingTimeInterval(4 * 24 * 3600),
            products: [
                GrokProductUsage(product: "GrokBuild", utilization: 0.31),
                GrokProductUsage(product: "GrokChat", utilization: 0.08),
                GrokProductUsage(product: "Api", utilization: 0.03)
            ],
            prepaidBalance: 12.5,
            onDemandCap: 25,
            onDemandUsed: 0,
            topUpMethod: "TOP_UP_METHOD_SAVED_PAYMENT_METHOD",
            planDisplayName: "SuperGrok",
            isUnifiedBilling: true,
            monthlyUsed: nil,
            monthlyLimit: nil,
            monthlyResetsAt: nil,
            fetchedAt: now
        )
    }
}
