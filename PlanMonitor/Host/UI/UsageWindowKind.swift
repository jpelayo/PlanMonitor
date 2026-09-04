import Foundation

/// How long the window behind a usage gauge runs. Only a window measured in days can be read
/// against a daily pace, so only `.multiDay` earns the segment hints of `SegmentedUsageBar`.
///
/// **This is a declaration, not an inference, and deliberately so.** The tempting shortcut is to
/// classify from the reset timestamp — "resets in six days, therefore weekly". That works in one
/// direction only: a reset more than `hourlyUpperBound` away cannot belong to a 5-hour window, but
/// a *weekly* window an hour from rolling over is indistinguishable from an hourly one by that
/// measure alone. Since a gauge is read continuously, and every multi-day window spends its last
/// hours looking exactly like a short one, reset-time inference would drop the segments right when
/// the bar is fullest. Nor is the field name a safe proxy: Codex's `sevenDayOpus*` fields hold a
/// model-scoped **5-hour** window, the names being leftovers from the Claude donor model.
///
/// So the kind is declared where it is actually known:
/// - **Claude** — statically per call site; each window is a distinct, known field.
/// - **Codex** — by slot. `CodexUsagePollingService.mapLimitsToSlots` decides hourly vs weekly when
///   it assigns slots (`fiveHourScore` / `modelFiveHourScore` vs `sevenDayScore` / `modelWeeklyScore`),
///   so the slot, never the field name, carries the meaning.
/// - **Grok** — statically: the weekly pool segments, the monthly allowance does not.
///
/// `.unknown` is the safe default: an unclassified window draws the plain bar. Showing seven
/// segments on a window that is not seven days long is worse than showing none.
enum UsageWindowKind: Sendable {
    /// A window measured in hours — Claude's and Codex's 5-hour limits.
    case hourly
    /// A window measured in days, whose quota can be paced daily.
    case multiDay
    /// Not classified. Draws the plain bar.
    case unknown

    /// The longest an hourly window can plausibly run, with an hour of slack for clock skew and
    /// rounding in the reported reset. Used only to *sanity-check* a declaration, never to make one.
    static let hourlyUpperBound: TimeInterval = 6 * 3600

    /// Every multi-day window tracked today runs a week.
    static let sevenDays: TimeInterval = 7 * 24 * 3600

    var showsDailySegments: Bool {
        self == .multiDay
    }

    /// How far through the window we are, 0...1 — where the fill *would* be if the quota were
    /// spent evenly. Only the window's *end* is reported by any provider, so the start is
    /// `resetsAt - duration` and the duration has to be declared, never inferred: a wrong duration
    /// puts the marker visibly in the wrong place.
    static func elapsedFraction(resetsAt: Date?, duration: TimeInterval?, now: Date = Date()) -> Double? {
        guard let resetsAt, let duration, duration > 0 else { return nil }
        let elapsed = (duration - resetsAt.timeIntervalSince(now)) / duration
        guard elapsed.isFinite else { return nil }
        return min(max(elapsed, 0), 1)
    }

    /// True when `resetsAt` is too far out for `self` to be honest about being hourly — a cheap
    /// contradiction check for a declaration, not a classifier. A `false` result proves nothing.
    func contradictedByReset(_ resetsAt: Date?, now: Date = Date()) -> Bool {
        guard self == .hourly, let resetsAt else { return false }
        return resetsAt.timeIntervalSince(now) > Self.hourlyUpperBound
    }
}
