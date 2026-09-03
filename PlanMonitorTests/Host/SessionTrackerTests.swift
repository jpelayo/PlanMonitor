import Foundation
import Testing
@testable import PlanTracker

@MainActor
struct SessionTrackerTests {
    private static let resetHour = 4
    private static let interval: TimeInterval = 300

    /// Today at 10:00 local: safely past `resetHour`, so the first tick's implicit daily
    /// reset is deterministic regardless of when the tests run.
    private static var base: Date {
        Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
    }

    private static func tick(_ tracker: SessionTracker, at date: Date, percent: Double) {
        tracker.processTick(
            signals: [ActivitySignal.percent("weekly", percent)!],
            minInterval: interval,
            resetHour: resetHour,
            now: date
        )
    }

    // MARK: - Namespacing

    @Test func trackersInDifferentNamespacesDoNotShareKeys() {
        withDefaults { defaults in
            let a = SessionTracker(namespace: "a", defaults: defaults)
            let b = SessionTracker(namespace: "b", defaults: defaults)
            let t0 = Self.base

            Self.tick(a, at: t0, percent: 10)
            Self.tick(a, at: t0.addingTimeInterval(300), percent: 20)
            Self.tick(a, at: t0.addingTimeInterval(600), percent: 20)
            Self.tick(a, at: t0.addingTimeInterval(900), percent: 20)

            #expect(a.accumulatedSeconds == 600)
            #expect(b.accumulatedSeconds == 0)
            #expect(defaults.double(forKey: "a.session.accumulatedSeconds") == 600)
            #expect(defaults.object(forKey: "b.session.accumulatedSeconds") == nil)
            #expect(defaults.dictionary(forKey: "a.session.lastKnownSignals") != nil)
            #expect(defaults.object(forKey: "b.session.lastKnownSignals") == nil)

            // A relaunch reads back its own namespace only.
            #expect(SessionTracker(namespace: "a", defaults: defaults).accumulatedSeconds == 600)
            #expect(SessionTracker(namespace: "b", defaults: defaults).accumulatedSeconds == 0)
        }
    }

    // MARK: - Quantum

    @Test func percentSignalBucketsAtATenthOfAPoint() {
        #expect(ActivitySignal.percent("p", 10.0)?.quantum == 0.1)
        #expect(ActivitySignal.percent("p", 10.0)?.bucket == 100)
        #expect(ActivitySignal.percent("p", 10.04)?.bucket == 100)
        #expect(ActivitySignal.percent("p", 10.1)?.bucket == 101)
        #expect(ActivitySignal.percent("p", nil) == nil)
    }

    @Test func subQuantumMovementIsNotActivity() {
        withDefaults { defaults in
            let tracker = SessionTracker(namespace: "q", defaults: defaults)
            let t0 = Self.base

            Self.tick(tracker, at: t0, percent: 10.0)
            Self.tick(tracker, at: t0.addingTimeInterval(300), percent: 10.04)
            Self.tick(tracker, at: t0.addingTimeInterval(600), percent: 10.04)
            Self.tick(tracker, at: t0.addingTimeInterval(900), percent: 10.04)

            #expect(tracker.accumulatedSeconds == 0)
        }
    }

    @Test func aTenthOfAPointIsActivity() {
        withDefaults { defaults in
            let tracker = SessionTracker(namespace: "q", defaults: defaults)
            let t0 = Self.base

            Self.tick(tracker, at: t0, percent: 10.0)
            Self.tick(tracker, at: t0.addingTimeInterval(300), percent: 10.1)
            Self.tick(tracker, at: t0.addingTimeInterval(600), percent: 10.1)
            Self.tick(tracker, at: t0.addingTimeInterval(900), percent: 10.1)

            #expect(tracker.accumulatedSeconds == 600)
        }
    }

    // MARK: - Segments

    @Test func twoQuietTicksCloseASegmentAndAddWallTime() {
        withDefaults { defaults in
            let tracker = SessionTracker(namespace: "s", defaults: defaults)
            let t0 = Self.base

            Self.tick(tracker, at: t0, percent: 10) // baseline
            Self.tick(tracker, at: t0.addingTimeInterval(300), percent: 20) // segment opens
            Self.tick(tracker, at: t0.addingTimeInterval(600), percent: 30) // still active
            Self.tick(tracker, at: t0.addingTimeInterval(900), percent: 30) // quiet 1
            #expect(tracker.accumulatedSeconds == 0)
            Self.tick(tracker, at: t0.addingTimeInterval(1200), percent: 30) // quiet 2 → close
            #expect(tracker.accumulatedSeconds == 900)

            // A single quiet tick between two moves does not close the segment.
            Self.tick(tracker, at: t0.addingTimeInterval(1500), percent: 40)
            Self.tick(tracker, at: t0.addingTimeInterval(1800), percent: 40)
            Self.tick(tracker, at: t0.addingTimeInterval(2100), percent: 50)
            Self.tick(tracker, at: t0.addingTimeInterval(2400), percent: 50)
            Self.tick(tracker, at: t0.addingTimeInterval(2700), percent: 50)
            #expect(tracker.accumulatedSeconds == 900 + 1200)
        }
    }

    @Test func minIntervalGateDropsEarlyTicks() {
        withDefaults { defaults in
            let tracker = SessionTracker(namespace: "g", defaults: defaults)
            let t0 = Self.base

            Self.tick(tracker, at: t0, percent: 10)
            // 100s < half of 300s: dropped, so it neither starts a segment nor moves the baseline.
            Self.tick(tracker, at: t0.addingTimeInterval(100), percent: 20)
            Self.tick(tracker, at: t0.addingTimeInterval(300), percent: 20) // movement vs baseline 10
            Self.tick(tracker, at: t0.addingTimeInterval(600), percent: 20)
            Self.tick(tracker, at: t0.addingTimeInterval(900), percent: 20)

            // Had the early tick counted, the segment would have run 100→600 (500s).
            #expect(tracker.accumulatedSeconds == 600)
        }
    }

    // MARK: - Daily reset

    @Test func dailyResetClearsAccumulatedTimeAndReseedsBaselines() {
        withDefaults { defaults in
            let tracker = SessionTracker(namespace: "d", defaults: defaults)
            let day1 = Self.base
            let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!

            Self.tick(tracker, at: day1, percent: 10)
            Self.tick(tracker, at: day1.addingTimeInterval(300), percent: 20)
            Self.tick(tracker, at: day1.addingTimeInterval(600), percent: 20)
            Self.tick(tracker, at: day1.addingTimeInterval(900), percent: 20)
            #expect(tracker.accumulatedSeconds == 600)

            // Next day, past the reset hour: everything goes, and this tick is a baseline only.
            Self.tick(tracker, at: day2, percent: 50)
            #expect(tracker.accumulatedSeconds == 0)
            #expect(defaults.double(forKey: "d.session.accumulatedSeconds") == 0)
            #expect(defaults.double(forKey: "d.session.lastResetDate") == day2.timeIntervalSince1970)
            let reseeded = defaults.dictionary(forKey: "d.session.lastKnownSignals")
            #expect(reseeded?["weekly"] as? Double == ActivitySignal.percent("weekly", 50)?.bucket)

            // Movement against the re-seeded baseline counts again.
            Self.tick(tracker, at: day2.addingTimeInterval(300), percent: 60)
            Self.tick(tracker, at: day2.addingTimeInterval(600), percent: 60)
            Self.tick(tracker, at: day2.addingTimeInterval(900), percent: 60)
            #expect(tracker.accumulatedSeconds == 600)
        }
    }

    @Test func noResetBeforeTheResetHourOnTheSameDay() {
        withDefaults { defaults in
            let tracker = SessionTracker(namespace: "d", defaults: defaults)
            let t0 = Self.base

            Self.tick(tracker, at: t0, percent: 10)
            Self.tick(tracker, at: t0.addingTimeInterval(300), percent: 20)
            Self.tick(tracker, at: t0.addingTimeInterval(600), percent: 20)
            Self.tick(tracker, at: t0.addingTimeInterval(900), percent: 20)

            // Later the same day, still before tomorrow's reset moment.
            Self.tick(tracker, at: t0.addingTimeInterval(6 * 3600), percent: 20)
            #expect(tracker.accumulatedSeconds == 600)
        }
    }

    // MARK: - Signals

    @Test func decimalAmountBucketsAtCents() {
        let signal = ActivitySignal.amount("x", Decimal(string: "1.234"))
        #expect(signal?.value == 123)
        #expect(signal?.quantum == 1)
        #expect(signal?.bucket == 123)
        #expect(ActivitySignal.amount("x", Decimal(string: "1.236"))?.bucket == 124)
        #expect(ActivitySignal.amount("x", nil as Decimal?) == nil)
        #expect(ActivitySignal.amount("y", 12.5 as Double?)?.bucket == 1250)
        #expect(ActivitySignal.minorUnits("z", 42)?.bucket == 42)
    }

    @Test func grokSignalsUsePercentAndCents() {
        let usage = DemoGrokUsage.snapshot() // weekly 0.42, prepaid 12.5, onDemand 0
        let signals = GrokUsageViewModel.activitySignals(for: usage)
        let byID = Dictionary(uniqueKeysWithValues: signals.map { ($0.id, $0) })

        #expect(byID["weekly"]?.value == 42)
        #expect(byID["weekly"]?.quantum == 0.1)
        #expect(byID["prepaid"]?.value == 1250)
        #expect(byID["prepaid"]?.quantum == 1)
        #expect(byID["onDemand"]?.value == 0)
        #expect(byID["monthly"] == nil)
    }

    @Test func grokSignalsFallBackToMonthlyPercentWithoutWeeklyPool() {
        var usage = GrokUsageData.empty
        usage.monthlyUsed = 25
        usage.monthlyLimit = 100
        let signals = GrokUsageViewModel.activitySignals(for: usage)

        #expect(signals.map(\.id) == ["monthly"])
        #expect(signals.first?.value == 25)
        #expect(signals.first?.quantum == 0.1)
    }

    @Test func openRouterSignalsUseLifetimeSpendNeverRemaining() {
        var snapshot = OpenRouterSnapshot.empty
        snapshot.accountCredit = AccountCredit(totalPurchased: 100, totalUsed: Decimal(string: "13.59")!)
        snapshot.spentToday = Decimal(string: "0.50")

        let signals = OpenRouterBudgetViewModel.activitySignals(for: snapshot)
        let byID = Dictionary(uniqueKeysWithValues: signals.map { ($0.id, $0) })

        #expect(byID["totalUsed"]?.value == 1359)
        #expect(byID["totalUsed"]?.quantum == 1)
        #expect(byID["spentToday"]?.value == 50)
        #expect(byID["remaining"] == nil)

        // A top-up changes `remaining` but must not read as activity.
        snapshot.accountCredit = AccountCredit(totalPurchased: 500, totalUsed: Decimal(string: "13.59")!)
        #expect(OpenRouterBudgetViewModel.activitySignals(for: snapshot) == signals)

        // Sub-cent residue today collapses to a zero bucket rather than jittering.
        snapshot.spentToday = Decimal(string: "0.004")
        let residue = OpenRouterBudgetViewModel.activitySignals(for: snapshot)
        #expect(residue.first { $0.id == "spentToday" }?.value == 0)
    }

    // MARK: - Formatting

    @Test func sessionTimeLineHidesUnderAMinute() {
        #expect(SessionTimeFormatter.line(totalSeconds: 0) == nil)
        #expect(SessionTimeFormatter.line(totalSeconds: 59.9) == nil)
    }

    @Test func sessionTimeLineFormatsHoursAndMinutes() {
        let prefix = String(localized: "Today's usage:")
        #expect(SessionTimeFormatter.line(totalSeconds: 60) == prefix + " " + String(localized: "\(1)m"))
        #expect(SessionTimeFormatter.line(totalSeconds: 4980) == prefix + " " + String(localized: "\(1)h \(23)m"))
    }

    // MARK: - Migration

    @Test func legacyClaudeKeysAreVisibleAfterHostMigration() {
        withDefaults { defaults in
            let lastReset = Self.base.timeIntervalSince1970
            defaults.set(1234.0, forKey: "sessionAccumulatedSeconds")
            defaults.set(lastReset, forKey: "sessionLastResetDate")

            HostMigration.run(defaults: defaults)
            let tracker = SessionTracker(namespace: "claude", defaults: defaults)

            #expect(tracker.accumulatedSeconds == 1234)
            #expect(tracker.totalSeconds == 1234)
            #expect(defaults.double(forKey: "claude.session.lastResetDate") == lastReset)
            #expect(defaults.double(forKey: "sessionAccumulatedSeconds") == 1234)
        }
    }

    @Test func mockAccumulatedIsNotPersisted() {
        withDefaults { defaults in
            let tracker = SessionTracker(namespace: "m", defaults: defaults)
            tracker.setMockAccumulated(5000)
            #expect(tracker.totalSeconds == 5000)
            #expect(defaults.object(forKey: "m.session.accumulatedSeconds") == nil)
        }
    }
}
