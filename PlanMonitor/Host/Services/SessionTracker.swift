import Foundation

/// One observed quantity whose movement means "the user is working". `quantum` is the
/// smallest change that counts: 0.1 for a percentage, 1 for an amount in cents.
nonisolated struct ActivitySignal: Sendable, Equatable {
    let id: String
    let value: Double
    let quantum: Double

    init(id: String, value: Double, quantum: Double) {
        self.id = id
        self.value = value
        self.quantum = quantum
    }

    /// Percent 0–100, sensitive to a tenth of a point.
    static func percent(_ id: String, _ value: Double?) -> ActivitySignal? {
        value.map { ActivitySignal(id: id, value: $0, quantum: 0.1) }
    }

    /// An integer amount in minor units (cents).
    static func minorUnits(_ id: String, _ value: Int?) -> ActivitySignal? {
        value.map { ActivitySignal(id: id, value: Double($0), quantum: 1) }
    }

    /// A decimal amount in major units, compared at cent resolution.
    static func amount(_ id: String, _ value: Decimal?) -> ActivitySignal? {
        guard let value else { return nil }
        let cents = NSDecimalNumber(decimal: value * 100).doubleValue
        return ActivitySignal(id: id, value: cents.rounded(), quantum: 1)
    }

    static func amount(_ id: String, _ value: Double?) -> ActivitySignal? {
        value.map { ActivitySignal(id: id, value: ($0 * 100).rounded(), quantum: 1) }
    }

    var bucket: Double {
        (value / quantum).rounded()
    }
}

/// Accumulates the time a provider is actively being used, inferred from movement in its
/// usage counters between polls. Provider-neutral: the provider decides which signals to feed.
///
/// The algorithm is unchanged from the original Claude tracker:
/// - a tick is dropped when it arrives sooner than half the detection interval;
/// - the day resets once `resetHour` (local calendar) has passed;
/// - movement in any signal opens or extends a segment;
/// - two consecutive quiet ticks close the segment and add its wall time.
///
/// All state is namespaced per provider so four trackers never share a key.
@MainActor
final class SessionTracker {
    private let defaults: UserDefaults
    private let keys: Keys

    private var lastKnown: [String: Double] = [:]
    private var noChangeCount = 0
    private var sessionStartTime: Date?
    private(set) var accumulatedSeconds: TimeInterval = 0
    private var lastResetDate: Date = .distantPast
    private var lastTickDate: Date = .distantPast

    private struct Keys {
        let accumulated: String
        let lastReset: String
        let lastKnown: String

        init(namespace: String) {
            accumulated = "\(namespace).session.accumulatedSeconds"
            lastReset = "\(namespace).session.lastResetDate"
            lastKnown = "\(namespace).session.lastKnownSignals"
        }
    }

    init(namespace: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keys = Keys(namespace: namespace)
        load()
    }

    /// Accumulated time plus the open segment, if any.
    var totalSeconds: TimeInterval {
        guard let start = sessionStartTime else { return accumulatedSeconds }
        return accumulatedSeconds + Date().timeIntervalSince(start)
    }

    func processTick(signals: [ActivitySignal], minInterval: TimeInterval, resetHour: Int, now: Date = Date()) {
        if lastTickDate != .distantPast {
            let elapsed = now.timeIntervalSince(lastTickDate)
            guard elapsed >= minInterval * 0.5 else { return }
        }
        lastTickDate = now

        checkDailyReset(now: now, resetHour: resetHour)

        let haveBaseline = !lastKnown.isEmpty
        let activityDetected = signals.contains { signal in
            guard let previous = lastKnown[signal.id] else { return false }
            return signal.bucket != previous
        }

        if haveBaseline && activityDetected {
            noChangeCount = 0
            if sessionStartTime == nil {
                sessionStartTime = now
            }
        } else if sessionStartTime != nil {
            noChangeCount += 1
            if noChangeCount >= 2 {
                if let start = sessionStartTime {
                    accumulatedSeconds += now.timeIntervalSince(start)
                }
                sessionStartTime = nil
                noChangeCount = 0
            }
        }

        for signal in signals {
            lastKnown[signal.id] = signal.bucket
        }
        persist()
    }

    /// Demo data. Not persisted.
    func setMockAccumulated(_ seconds: TimeInterval) {
        accumulatedSeconds = seconds
        sessionStartTime = nil
        noChangeCount = 0
    }

    // MARK: - Private

    private func checkDailyReset(now: Date, resetHour: Int) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = resetHour
        components.minute = 0
        components.second = 0

        guard let todayReset = calendar.date(from: components) else { return }
        guard now >= todayReset && lastResetDate < todayReset else { return }

        accumulatedSeconds = 0
        sessionStartTime = nil
        noChangeCount = 0
        lastKnown = [:]
        lastResetDate = now
        persist()
    }

    private func persist() {
        defaults.set(accumulatedSeconds, forKey: keys.accumulated)
        defaults.set(lastResetDate.timeIntervalSince1970, forKey: keys.lastReset)
        if lastKnown.isEmpty {
            defaults.removeObject(forKey: keys.lastKnown)
        } else {
            defaults.set(lastKnown, forKey: keys.lastKnown)
        }
    }

    private func load() {
        accumulatedSeconds = defaults.double(forKey: keys.accumulated)

        let resetTimestamp = defaults.double(forKey: keys.lastReset)
        if resetTimestamp > 0 {
            lastResetDate = Date(timeIntervalSince1970: resetTimestamp)
        }

        if let stored = defaults.dictionary(forKey: keys.lastKnown) {
            lastKnown = stored.compactMapValues { $0 as? Double }
        }

        // An open segment is not restored: a relaunch is an implicit session end.
        sessionStartTime = nil
    }
}
