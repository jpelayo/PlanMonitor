import AppKit
import Foundation
import Testing
@testable import PlanMonitor

/// The Go subscription's three windows: decoding, the menu bar, the ring, the tint, and how a poll
/// of two endpoints becomes one snapshot.
@Suite("OpenCode Go")
struct OpenCodeGoUsageTests {
    private static let fetchedAt = Date(timeIntervalSince1970: 1_792_000_000)

    // MARK: - Decoding

    @Test func theCapturedPayloadDecodes() throws {
        let go = try #require(try OpenCodeFixtures.go(OpenCodeFixtures.goUsage))

        #expect(go.rolling == OpenCodeGoWindow(usedPercent: 0, resetsAt: OpenCodeFixtures.utc("2026-10-22T22:29:03Z"), isRateLimited: false))
        #expect(go.weekly?.resetsAt == OpenCodeFixtures.utc("2026-10-26T00:00:00Z"))
        #expect(go.monthly?.resetsAt == OpenCodeFixtures.utc("2026-11-22T16:42:21Z"))
        #expect(!go.isRateLimited)
    }

    @Test func aRateLimitedWindowIsFull() throws {
        let go = try #require(try OpenCodeFixtures.go(OpenCodeFixtures.goUsageLimited))
        #expect(go.rolling?.isRateLimited == true)
        #expect(go.weekly?.isRateLimited == false)
        #expect(go.isRateLimited)
        #expect(go.worstUsedFraction == 1)
    }

    @Test func aFullWindowIsLimitedWhateverItsStatus() {
        #expect(OpenCodeGoWindow(status: "ok", percent: 100, resetsAt: nil).isRateLimited)
        #expect(OpenCodeGoWindow(status: "rate-limited", percent: 40, resetsAt: nil).effectivePercent == 100)
        #expect(OpenCodeGoWindow(status: nil, percent: 140, resetsAt: nil).usedPercent == 100)
        #expect(OpenCodeGoWindow(status: nil, percent: -5, resetsAt: nil).usedPercent == 0)
    }

    /// A window without a percentage is not reported, never 0%; no window at all is no Go.
    @Test func missingFieldsAreNotReported() throws {
        let partial = try #require(try OpenCodeFixtures.go(#"{"usage":{"rolling":{"status":"ok"},"weekly":{"percent":"12"}}}"#))
        #expect(partial.rolling == nil)
        #expect(partial.weekly?.usedPercent == 12)
        #expect(partial.monthly == nil)

        #expect(try OpenCodeFixtures.go(#"{"usage":{}}"#) == nil)
        #expect(try OpenCodeFixtures.go(#"{}"#) == nil)
    }

    // MARK: - Menu bar

    private func text(_ display: OpenCodeMenuBarDisplay, _ go: OpenCodeGoUsage?, remaining: Bool = false) -> String? {
        OpenCodeMenuBarDigits.resolve(display: display, go: go, showRemainingPercent: remaining).text
    }

    @Test func eachChoiceReadsItsWindowInEitherSense() throws {
        let go = try OpenCodeFixtures.go(OpenCodeFixtures.goUsageLimited)
        #expect(text(.goRolling, go) == "100%")
        #expect(text(.goWeekly, go) == "61%")
        #expect(text(.goMonthly, go) == "24%")
        #expect(text(.goRolling, go, remaining: true) == "0%")
        #expect(text(.goWeekly, go, remaining: true) == "39%")
        #expect(text(.goMonthly, go, remaining: true) == "76%")
        #expect(OpenCodeMenuBarDisplay.default == .goRolling)
    }

    @Test func aMissingWindowFallsBackToTheNearestOne() {
        let weeklyOnly = OpenCodeGoUsage(weekly: OpenCodeGoWindow(usedPercent: 61, resetsAt: nil, isRateLimited: false))
        #expect(text(.goRolling, weeklyOnly) == "61%")
        #expect(text(.goMonthly, weeklyOnly) == "61%")

        let monthlyOnly = OpenCodeGoUsage(monthly: OpenCodeGoWindow(usedPercent: 24, resetsAt: nil, isRateLimited: false))
        #expect(text(.goRolling, monthlyOnly) == "24%")
    }

    @Test func noGoDrawsNothing() {
        for display in OpenCodeMenuBarDisplay.allCases {
            let resolved = OpenCodeMenuBarDigits.resolve(display: display, go: nil, showRemainingPercent: false)
            #expect(resolved.text == nil, "\(display.rawValue)")
            #expect(resolved.severityFraction == nil)
        }
    }

    @Test func severityIsTheUsedShareWhateverTheSense() throws {
        let go = try OpenCodeFixtures.go(OpenCodeFixtures.goUsageLimited)
        let resolved = OpenCodeMenuBarDigits.resolve(display: .goWeekly, go: go, showRemainingPercent: true)
        #expect(resolved.severityFraction == 0.61)
    }

    // MARK: - Ring and tint

    @Test func goRingsFillWithWhatIsLeft() throws {
        var snapshot = OpenCodeSnapshot.empty
        snapshot.go = try OpenCodeFixtures.go(OpenCodeFixtures.goUsageLimited)
        #expect(OpenCodeRingSource.goRolling.fill(for: snapshot) == 0)
        // 1 − 0.61 = 0.39, five dashes of twelve.
        #expect(OpenCodeRingSource.goWeekly.fill(for: snapshot) == 5.0 / 12.0)
        #expect(OpenCodeRingSource.goMonthly.fill(for: snapshot) == 9.0 / 12.0)
        #expect(OpenCodeRingSource.goWeekly.fill(for: .empty) == nil)
    }

    /// The icon is the tightest of everything: a rate-limited Go window is red with the budget fine.
    @Test func theIconTakesTheWorstOfGoAndBudget() throws {
        var snapshot = OpenCodeSnapshot.assemble(
            members: try OpenCodeFixtures.members(OpenCodeFixtures.docsExample),
            go: try OpenCodeFixtures.go(OpenCodeFixtures.goUsageLimited),
            selectedMemberID: nil,
            fetchedAt: Self.fetchedAt
        )
        func tint() -> NSColor? {
            OpenCodeMenuBarLabel.make(
                snapshot: snapshot,
                connectionState: .connected(keyPrefix: "oc_sk_0123456789ab"),
                display: .goWeekly,
                showRemainingPercent: false,
                ringFill: nil,
                font: MenuBarLabel.defaultFont
            ).symbolTint
        }
        #expect(tint() == .systemRed)

        snapshot.go = OpenCodeGoUsage(rolling: OpenCodeGoWindow(usedPercent: 10, resetsAt: nil, isRateLimited: false))
        #expect(tint() == .systemGreen)              // 10% of Go, 17% of the budget
    }

    // MARK: - Window lengths

    @Test func theMonthlyWindowRunsOneCalendarMonthBackFromItsReset() throws {
        let reset = OpenCodeFixtures.utc("2026-11-22T16:42:21Z")
        let duration = try #require(OpenCodeGoUsage.monthlyDuration(endingAt: reset))
        #expect(duration == 31 * 24 * 3600)          // 22 Oct → 22 Nov
        #expect(OpenCodeGoUsage.monthlyDuration(endingAt: nil) == nil)
    }

    /// One bar segment per day of the window, whatever month it spans.
    @Test func theMonthlyBarHasOneSegmentPerDay() {
        #expect(OpenCodeGoUsage.monthlyDays(endingAt: OpenCodeFixtures.utc("2026-11-22T16:42:21Z")) == 31)
        #expect(OpenCodeGoUsage.monthlyDays(endingAt: OpenCodeFixtures.utc("2027-03-22T16:42:21Z")) == 28)
        #expect(OpenCodeGoUsage.monthlyDays(endingAt: OpenCodeFixtures.utc("2028-03-22T16:42:21Z")) == 29)
        #expect(OpenCodeGoUsage.monthlyDays(endingAt: OpenCodeFixtures.utc("2026-12-22T16:42:21Z")) == 30)
        #expect(OpenCodeGoUsage.monthlyDays(endingAt: nil) == nil)
    }

    // MARK: - One poll, two endpoints

    private static let members = [
        OpenCodeMemberBudget(userID: "u", email: "u@example.com", spent: 5, budget: 50, exceeded: false, resetsAt: nil, source: .custom)
    ]

    @Test func eitherHalfIsEnough() throws {
        // No Go and no budgets: this key reads nothing at all.
        let nothing = OpenCodePollOutcome.make(members: .failure(.missingScope), go: .success(nil), fetchedAt: Self.fetchedAt)
        #expect(nothing == .failure(.missingScope))

        let go = try #require(try OpenCodeFixtures.go(OpenCodeFixtures.goUsage))
        let outcome = try OpenCodePollOutcome.make(members: .failure(.missingScope), go: .success(go), fetchedAt: Self.fetchedAt).get()
        #expect(outcome.members == .unreadable)
        #expect(outcome.go == .read(go))

        let budgetsOnly = try OpenCodePollOutcome.make(members: .success(Self.members), go: .success(nil), fetchedAt: Self.fetchedAt).get()
        #expect(budgetsOnly.members == .read(Self.members))
        #expect(budgetsOnly.go == .unreadable)
    }

    @Test func aRefusedKeyIsDefinitiveFromEitherEndpoint() {
        #expect(OpenCodePollOutcome.make(members: .success(Self.members), go: .failure(.unauthorized), fetchedAt: Self.fetchedAt) == .failure(.unauthorized))
        #expect(OpenCodePollOutcome.make(members: .failure(.unauthorized), go: .success(nil), fetchedAt: Self.fetchedAt) == .failure(.unauthorized))
    }

    @Test func nothingReadIsAFailedCycle() {
        let offline = OpenCodeAPIError.network("offline")
        #expect(OpenCodePollOutcome.make(members: .failure(offline), go: .failure(offline), fetchedAt: Self.fetchedAt) == .failure(offline))
        #expect(OpenCodePollOutcome.make(members: .failure(.missingScope), go: .failure(offline), fetchedAt: Self.fetchedAt) == .failure(offline))
    }

    /// One endpoint failing never blanks the other: the half keeps what was on screen.
    @Test func aTransientHalfKeepsThePreviousFigures() throws {
        let go = try #require(try OpenCodeFixtures.go(OpenCodeFixtures.goUsage))
        let previous = OpenCodeSnapshot.assemble(members: Self.members, go: go, selectedMemberID: nil, fetchedAt: Self.fetchedAt)
        let later = Self.fetchedAt.addingTimeInterval(300)

        let budgetsBlipped = OpenCodeSnapshot.merging(previous: previous, members: .unchanged, go: .read(go), selectedMemberID: nil, fetchedAt: later)
        #expect(budgetsBlipped.budget == 50)
        #expect(budgetsBlipped.go == go)
        #expect(budgetsBlipped.fetchedAt == later)

        let goBlipped = OpenCodeSnapshot.merging(previous: previous, members: .read(Self.members), go: .unchanged, selectedMemberID: nil, fetchedAt: later)
        #expect(goBlipped.go == go)

        let goGone = OpenCodeSnapshot.merging(previous: previous, members: .read(Self.members), go: .unreadable, selectedMemberID: nil, fetchedAt: later)
        #expect(goGone.go == nil)

        let budgetsRefused = OpenCodeSnapshot.merging(previous: previous, members: .unreadable, go: .read(go), selectedMemberID: nil, fetchedAt: later)
        #expect(!budgetsRefused.budgetsReadable)
        #expect(!budgetsRefused.hasSpend)
        #expect(budgetsRefused.go == go)
    }

    // MARK: - Session time

    @MainActor
    @Test func goPercentagesAndSpendFeedTheSessionTracker() throws {
        let snapshot = OpenCodeSnapshot.assemble(
            members: Self.members,
            go: try OpenCodeFixtures.go(OpenCodeFixtures.goUsageLimited),
            selectedMemberID: nil,
            fetchedAt: Self.fetchedAt
        )
        let ids = OpenCodeViewModel.activitySignals(for: snapshot).map(\.id)
        #expect(ids == ["goRolling", "goWeekly", "goMonthly", "spent"])
    }
}
