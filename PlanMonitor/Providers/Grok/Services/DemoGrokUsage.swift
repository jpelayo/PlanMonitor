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
            // Announces itself as automatic, so demo mode actually renders the auto-top-up row
            // (`GrokMenuBarView`) that App Review sees. A saved payment method is only a way
            // credits *can* be bought, and `isAutoTopUpEnabled` deliberately reads that as off —
            // which is why the real captured value lives in the parser's fixture, not here.
            topUpMethod: "TOP_UP_METHOD_AUTOMATIC",
            planDisplayName: "SuperGrok",
            isUnifiedBilling: true,
            monthlyUsed: nil,
            monthlyLimit: nil,
            monthlyResetsAt: nil,
            fetchedAt: now
        )
    }
}
