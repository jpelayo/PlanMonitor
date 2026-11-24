import Foundation
import Testing
@testable import PlanMonitor

/// agy's report → groups and buckets, read as used, with nothing invented.
@Suite("Google AI usage report")
struct GoogleAIUsageReportTests {

    @Test func theRealReportGivesThreeGroupsAndFiveBuckets() throws {
        let usage = try GoogleAIUsageReport.parse(GoogleAIFixtures.report)
        #expect(usage.groups.map(\.name) == ["Gemini Models", "Claude and GPT models", "Gemini 4 Argon"])
        #expect(usage.buckets.map(\.id) == ["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h", "gemini-argon-wtu-weekly"])
        #expect(usage.buckets.map(\.kind) == [.weekly, .fiveHour, .weekly, .fiveHour, .weekly])
    }

    @Test func usedIsOneMinusRemaining() throws {
        let usage = try GoogleAIUsageReport.parse(GoogleAIFixtures.report)
        let fiveHour = try #require(usage.geminiFiveHour)
        #expect(fiveHour.id == "gemini-5h")
        #expect(abs(fiveHour.used - 0.4521151781082153) < 1e-9)
        #expect(fiveHour.resetsAt == ISO8601DateFormatter().date(from: "2026-11-23T18:30:18Z"))
    }

    @Test func anUntouchedWindowShowsNoResetAndNoMarker() throws {
        let usage = try GoogleAIUsageReport.parse(GoogleAIFixtures.report)
        let untouched = try #require(usage.buckets.first { $0.id == "3p-weekly" })
        #expect(untouched.isUnstarted)
        #expect(untouched.shownReset == nil)
        #expect(untouched.paceFraction() == nil)
        let started = try #require(usage.buckets.first { $0.id == "gemini-weekly" })
        #expect(started.shownReset != nil)
    }

    @Test func theWeeklyMarkerSitsWhereTheWeekIs() throws {
        let reset = Date(timeIntervalSince1970: 1_000_000)
        let bucket = GoogleAIBucket(id: "w", group: "G", name: "w", kind: .weekly, remaining: 0.5, resetsAt: reset)
        // Two days left of seven: five sevenths elapsed.
        let marker = try #require(bucket.paceFraction(now: reset.addingTimeInterval(-2 * 86400)))
        #expect(abs(marker - 5.0 / 7.0) < 1e-9)
    }

    @Test func anUnknownWindowIsKeptUnderItsOwnName() throws {
        let json = #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"x-daily","name":"Daily Limit","window":"daily","remaining_fraction":0.25}]}]}}}"#
        let usage = try GoogleAIUsageReport.parse(Data(json.utf8))
        let bucket = try #require(usage.buckets.first)
        #expect(bucket.kind == .other("daily"))
        #expect(bucket.name == "Daily Limit")
        #expect(bucket.resetsAt == nil)
        #expect(abs(bucket.used - 0.75) < 1e-9)
    }

    @Test func aBucketWithoutAFractionIsLeftOutNotReadAsZero() throws {
        let json = #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"a","window":"5h"},{"id":"b","window":"weekly","remaining_fraction":0.5}]}]}}}"#
        let usage = try GoogleAIUsageReport.parse(Data(json.utf8))
        #expect(usage.buckets.map(\.id) == ["b"])
    }

    @Test(arguments: [
        #"{"status":"ERROR","command":{"name":"usage","data":{"groups":[]}}}"#,
        #"{"status":"SUCCESS","command":{"name":"help","data":{"groups":[]}}}"#,
        #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[]}}}"#,
        #"{"status":"SUCCESS","command":{"name":"usage","data":{}}}"#,
        "not json at all"
    ])
    func anythingElseIsAChangedReport(_ text: String) {
        #expect(throws: GoogleAIRunError.reportChanged) {
            try GoogleAIUsageReport.parse(Data(text.utf8))
        }
    }

    @Test func theFiveHourFallbackFindsAGeminiGroupByName() throws {
        let json = #"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Claude and GPT models","buckets":[{"id":"3p-5h","window":"5h","remaining_fraction":0.1}]},{"name":"Gemini Models","buckets":[{"id":"g-five","window":"5h","remaining_fraction":0.6}]}]}}}"#
        let usage = try GoogleAIUsageReport.parse(Data(json.utf8))
        #expect(usage.geminiFiveHour?.id == "g-five")
    }

    @Test func classifyPrefersAReportOnStdoutWhateverTheExit() {
        let failure = NSError(domain: NSPOSIXErrorDomain, code: 1)
        let ok = UserUnixTaskGoogleAIRunner.classify(error: failure, stdout: GoogleAIFixtures.report, stderr: Data())
        #expect((try? ok.get()) == GoogleAIFixtures.report)

        let missing = UserUnixTaskGoogleAIRunner.classify(
            error: NSError(domain: NSPOSIXErrorDomain, code: 127),
            stdout: Data(),
            stderr: Data("PLANMONITOR_AGY_NOT_FOUND\n".utf8)
        )
        #expect(missing == .failure(.agyNotFound))

        let failed = UserUnixTaskGoogleAIRunner.classify(error: failure, stdout: Data(), stderr: Data("whatever".utf8))
        #expect(failed == .failure(.agyFailed(exit: 1)))
    }
}
