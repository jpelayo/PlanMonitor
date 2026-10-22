import Foundation
import Testing
@testable import PlanMonitor

/// `status.opencode.ai/api/status`: only the top-level rollup is read.
@Suite("OpenCode status")
struct OpenCodeStatusTests {
    /// The real document of 2026-10-22, trimmed to one component: the rollup said degraded while
    /// the console component said operational, and the rollup is what the pill shows.
    private static let trimmed = #"""
    {"updatedAt":1792691657267,"since":1792028534694,"stale":false,"status":"degraded","components":[{"service":"console","status":"operational","reason":"none","since":1792689317266,"models":[],"breakdown":[],"speed":{}}]}
    """#

    @Test func theRollupWinsOverComponents() throws {
        #expect(try OpenCodeStatusService.parse(Data(Self.trimmed.utf8)) == .degraded)
    }

    @Test func eachKnownStatusMaps() throws {
        func parse(_ status: String) throws -> OpenCodeSystemStatus {
            try OpenCodeStatusService.parse(Data(#"{"status":"\#(status)"}"#.utf8))
        }
        #expect(try parse("operational") == .operational)
        #expect(try parse("degraded") == .degraded)
        #expect(try parse("outage") == .outage)
        // Unseen states read as "something may be wrong", never green.
        #expect(try parse("maintenance") == .degraded)
    }

    @Test func aMalformedDocumentThrows() {
        #expect(throws: (any Error).self) {
            try OpenCodeStatusService.parse(Data(#"{"components":[]}"#.utf8))
        }
    }
}
