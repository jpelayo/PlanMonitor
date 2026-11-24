import Foundation
import Testing
@testable import PlanMonitor

/// The bar shows the Gemini models' 5-hour window (user decision 2026-11-23), in the global sense.
@Suite("Google AI menu bar")
@MainActor
struct GoogleAIMenuBarTests {

    private var usage: GoogleAIUsage { (try? GoogleAIUsageReport.parse(GoogleAIFixtures.report)) ?? .empty }

    @Test func usedModeShowsTheGeminiFiveHourUsed() {
        let digits = GoogleAIMenuBarDigits.resolve(usage: usage, showRemainingPercent: false)
        #expect(digits.text == "45%")
        #expect(abs((digits.severityFraction ?? 0) - 0.4521151781082153) < 1e-9)
    }

    @Test func remainingModeShowsWhatIsLeft() {
        let digits = GoogleAIMenuBarDigits.resolve(usage: usage, showRemainingPercent: true)
        #expect(digits.text == "54%")
        // Tint still means used, whichever sense the digits read in.
        #expect(abs((digits.severityFraction ?? 0) - 0.4521151781082153) < 1e-9)
    }

    @Test func noGeminiFiveHourDrawsNothingNeverZero() {
        let digits = GoogleAIMenuBarDigits.resolve(usage: .empty, showRemainingPercent: false)
        #expect(digits.text == nil)
        #expect(digits.severityFraction == nil)
    }

    @Test func wholePercentsAreNotLostToFloatingPoint() {
        let bucket = GoogleAIBucket(id: "gemini-5h", group: "Gemini Models", name: "", kind: .fiveHour, remaining: 0.71, resetsAt: nil)
        let digits = GoogleAIMenuBarDigits.resolve(usage: GoogleAIUsage(groups: [GoogleAIGroup(name: "Gemini Models", buckets: [bucket])]), showRemainingPercent: false)
        #expect(digits.text == "29%")
    }

    @Test func setupStateShowsNoFigures() {
        let label = GoogleAIMenuBarLabel.make(usage: usage, showsUsage: false, showRemainingPercent: false, font: MenuBarLabel.defaultFont)
        #expect(label.text == nil)
        #expect(label.symbolTint == GoogleAISeverity.normal.iconTint)
    }

    @Test func theGlyphTakesTheWorstBucket() {
        let worst = GoogleAIBucket(id: "3p-weekly", group: "Claude and GPT models", name: "", kind: .weekly, remaining: 0.05, resetsAt: nil)
        var tight = usage
        tight.groups.append(GoogleAIGroup(name: "Claude and GPT models", buckets: [worst]))
        let label = GoogleAIMenuBarLabel.make(usage: tight, showsUsage: true, showRemainingPercent: false, font: MenuBarLabel.defaultFont)
        #expect(label.symbolTint == GoogleAISeverity.critical.iconTint)
        #expect(label.text == "45%")
    }
}
