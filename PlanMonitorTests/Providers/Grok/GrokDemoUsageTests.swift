import Foundation
import Testing
@testable import PlanTracker

/// Ported from the standalone Grok app's smoke test: the demo snapshot must be complete
/// enough to drive the whole menu.
struct GrokDemoUsageTests {
    @Test func demoSnapshotHasWeeklyUsage() {
        let usage = DemoGrokUsage.snapshot()
        #expect(usage.hasWeeklyUsage)
        #expect(usage.planDisplayName == "SuperGrok")
        #expect(!usage.sortedProducts.isEmpty)
    }

    @Test func demoSnapshotProductsAreSortedByUtilizationDescending() {
        let products = DemoGrokUsage.snapshot().sortedProducts
        let utilizations = products.map(\.utilization)
        #expect(utilizations == utilizations.sorted(by: >))
        #expect(products.first?.product == "GrokBuild")
    }

    @Test func demoSnapshotCarriesExtraCreditsAndAutoTopUp() {
        let now = Date(timeIntervalSince1970: 1_756_720_000)
        let usage = DemoGrokUsage.snapshot(now: now)
        #expect(usage.usedPercent == 42)
        #expect(usage.hasExtraCredits)
        #expect(usage.isAutoTopUpEnabled)
        #expect(usage.isUnifiedBilling)
        #expect(usage.fetchedAt == now)
        #expect(usage.weeklyResetsAt == now.addingTimeInterval(4 * 24 * 3600))
    }
}
