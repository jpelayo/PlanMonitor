import Foundation

/// One limit as `agy /usage` reports it: a group's 5-hour or weekly window (or a kind agy adds
/// later, kept under its own name). Stored as agy gives it — the *remaining* fraction — and read
/// everywhere as used, like every other gauge.
nonisolated struct GoogleAIBucket: Codable, Equatable, Sendable, Identifiable {
    enum Kind: Codable, Equatable, Sendable {
        case fiveHour
        case weekly
        case other(String)

        init(window: String) {
            switch window.lowercased() {
            case "5h": self = .fiveHour
            case "weekly": self = .weekly
            default: self = .other(window)
            }
        }

        /// The window's length, which with the reset gives the pace marker. `nil` for an unknown kind.
        var duration: TimeInterval? {
            switch self {
            case .fiveHour: 5 * 3600
            case .weekly: 7 * 24 * 3600
            case .other: nil
            }
        }
    }

    /// agy's bucket id (`gemini-5h`, `3p-weekly`, …), unique within a report.
    let id: String
    /// The group's name, verbatim from agy ("Gemini Models"): Google's product names, untranslated.
    let group: String
    /// agy's own bucket name, shown only for a kind PlanMonitor does not know.
    let name: String
    let kind: Kind
    /// 0…1, as reported.
    let remaining: Double
    /// `nil` when agy gave none or the window has not started (nothing used yet).
    let resetsAt: Date?

    /// The used share, 0…1.
    var used: Double { min(max(1 - remaining, 0), 1) }

    /// A window with nothing used has not started: agy then reports "now + window" as the reset,
    /// a date that moves with every poll, so it is shown as no reset at all.
    var isUnstarted: Bool { used <= 0 }

    /// The reset worth showing: none for an unstarted window.
    var shownReset: Date? { isUnstarted ? nil : resetsAt }

    /// Where the pace marker sits, for a window of known length that has started.
    /// `UsageWindowKind.elapsedFraction`'s arithmetic, here because that type is main-actor bound.
    func paceFraction(now: Date = Date()) -> Double? {
        guard !isUnstarted, let resetsAt, let duration = kind.duration else { return nil }
        let elapsed = (duration - resetsAt.timeIntervalSince(now)) / duration
        guard elapsed.isFinite else { return nil }
        return min(max(elapsed, 0), 1)
    }
}

nonisolated struct GoogleAIGroup: Codable, Equatable, Sendable, Identifiable {
    let name: String
    let buckets: [GoogleAIBucket]
    var id: String { name }

    /// The order the gauges are drawn in (user request 2026-11-25): the 5-hour window above the
    /// weekly one, as every other provider shows them, then any kind agy adds, in agy's order.
    /// agy itself lists weekly first; `buckets` keeps its order.
    var shownBuckets: [GoogleAIBucket] {
        func rank(_ kind: GoogleAIBucket.Kind) -> Int {
            switch kind {
            case .fiveHour: 0
            case .weekly: 1
            case .other: 2
            }
        }
        return buckets.enumerated()
            .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
            .map(\.element)
    }
}

/// The whole report: agy's groups in agy's order.
nonisolated struct GoogleAIUsage: Codable, Equatable, Sendable {
    var groups: [GoogleAIGroup]

    static let empty = GoogleAIUsage(groups: [])

    var isEmpty: Bool { buckets.isEmpty }

    var buckets: [GoogleAIBucket] { groups.flatMap(\.buckets) }

    /// Every bucket in drawing order: groups in agy's order, each group's 5-hour window first.
    var shownBuckets: [GoogleAIBucket] { groups.flatMap(\.shownBuckets) }

    /// The bucket the menu bar shows (user decision 2026-11-23): the Gemini models' 5-hour
    /// window — by agy's id, else the first 5-hour window of a group whose name starts "Gemini".
    var geminiFiveHour: GoogleAIBucket? {
        if let byID = buckets.first(where: { $0.id == "gemini-5h" }) { return byID }
        return buckets.first { $0.kind == .fiveHour && $0.group.lowercased().hasPrefix("gemini") }
    }

    /// The most-used bucket, for the menu-bar glyph's tint.
    var worstUsedFraction: Double? { buckets.map(\.used).max() }
}
