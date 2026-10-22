import Foundation

/// One window of the OpenCode Go subscription, as `GET /inference/go/v1/usage` reports it.
///
/// The figures are the backend's own: a used percentage of the window's dollar allowance, floored
/// and capped at 100, and the moment the window resets. Per-model prices act as multipliers into a
/// single pool, so each window is one figure, never a per-model breakdown.
nonisolated struct OpenCodeGoWindow: Codable, Equatable, Sendable {
    /// 0–100.
    var usedPercent: Double
    var resetsAt: Date?
    /// The backend said `"rate-limited"`: Go requests stop until the reset, unless Extra usage is
    /// on and the credit balance takes over.
    var isRateLimited: Bool

    init(usedPercent: Double, resetsAt: Date?, isRateLimited: Bool) {
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
        self.isRateLimited = isRateLimited
    }

    /// From the API's own words. A full window is limited whatever the status says.
    init(status: String?, percent: Double, resetsAt: Date?) {
        self.init(
            usedPercent: percent,
            resetsAt: resetsAt,
            isRateLimited: status?.lowercased() == "rate-limited" || percent >= 100
        )
    }

    /// What the menu bar and the severity read: a limited window is a full one.
    var effectivePercent: Double {
        isRateLimited ? 100 : usedPercent
    }
}

/// The Go subscription's three windows. `nil` windows were not reported.
nonisolated struct OpenCodeGoUsage: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, CaseIterable, Sendable {
        /// The backend calls it `rolling`: five hours from the last recorded usage.
        case rolling
        /// Monday 00:00 UTC to Monday.
        case weekly
        /// Anchored to the subscription date, not the calendar month.
        case monthly
    }

    var rolling: OpenCodeGoWindow?
    var weekly: OpenCodeGoWindow?
    var monthly: OpenCodeGoWindow?

    static let rollingDuration: TimeInterval = 5 * 3600

    var isEmpty: Bool { rolling == nil && weekly == nil && monthly == nil }

    var windows: [OpenCodeGoWindow] { [rolling, weekly, monthly].compactMap { $0 } }

    var isRateLimited: Bool { windows.contains { $0.isRateLimited } }

    /// The tightest window, as a used fraction for the severity enum.
    var worstUsedFraction: Double? {
        windows.map(\.effectivePercent).max().map { $0 / 100 }
    }

    subscript(kind: Kind) -> OpenCodeGoWindow? {
        switch kind {
        case .rolling: rolling
        case .weekly: weekly
        case .monthly: monthly
        }
    }

    /// The window asked for, else the nearest one reported — so a choice never blanks while any
    /// window exists, the shared helpers' symmetric degradation extended to a third window.
    func window(preferring kind: Kind) -> OpenCodeGoWindow? {
        let order: [Kind]
        switch kind {
        case .rolling: order = [.rolling, .weekly, .monthly]
        case .weekly: order = [.weekly, .rolling, .monthly]
        case .monthly: order = [.monthly, .weekly, .rolling]
        }
        return order.lazy.compactMap { self[$0] }.first
    }

    /// How long the monthly window that ends at `resetsAt` runs: one calendar month back from its
    /// reset, in UTC, since the backend anchors it to the subscription date.
    static func monthlyDuration(endingAt resetsAt: Date?) -> TimeInterval? {
        guard let resetsAt else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(byAdding: .month, value: -1, to: resetsAt) else { return nil }
        return resetsAt.timeIntervalSince(start)
    }

    /// The monthly window's length in days — its bar's segments, one per day (user decision,
    /// 2026-10-22): 31 for 22 Oct → 22 Nov, 28 or 29 for a window ending in March.
    static func monthlyDays(endingAt resetsAt: Date?) -> Int? {
        monthlyDuration(endingAt: resetsAt).map { Int(($0 / 86_400).rounded()) }
    }
}
