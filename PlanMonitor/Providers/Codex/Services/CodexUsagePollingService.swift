//
//  CodexUsagePollingService.swift
//  PlanTracker
//

import Foundation

actor CodexUsagePollingService {
    private let apiClient: OpenAIAPIClient
    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 300
    private var cachedPlanTier: CodexPlanTier = .unknown
    /// Auto top-up moves rarely, so it rides the metadata cadence like the plan label.
    private var cachedAutoTopUp: OpenAIAutoTopUpSettings?
    private var lastMetadataRefreshAt: Date?
    private var metadataRefreshInterval: TimeInterval = 6 * 3600

    private var onUsageUpdate: (@Sendable (CodexUsageData) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?
    private var onSchedule: (@Sendable (Date?) -> Void)?
    private var intervalGeneration = 0
    private var nextFireAt: Date? {
        didSet { onSchedule?(nextFireAt) }
    }

    init(apiClient: OpenAIAPIClient) {
        self.apiClient = apiClient
    }

    func setCallbacks(
        onUsageUpdate: @escaping @Sendable (CodexUsageData) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        onSchedule: (@Sendable (Date?) -> Void)? = nil
    ) {
        self.onUsageUpdate = onUsageUpdate
        self.onError = onError
        self.onSchedule = onSchedule
    }

    /// Applies at once by interrupting the pending sleep; never forces a fetch.
    func setPollingInterval(_ interval: TimeInterval) {
        let clamped = Swift.max(60, interval)
        guard clamped != pollingInterval else { return }
        pollingInterval = clamped
        intervalGeneration &+= 1
    }

    func startPolling() {
        stopPolling()

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchUsage()
                await self.sleepUntilNextCycle()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        nextFireAt = nil
    }

    private func sleepUntilNextCycle() async {
        let start = Date()
        var generation = intervalGeneration
        var deadline = start.addingTimeInterval(pollingInterval)
        nextFireAt = deadline
        defer { nextFireAt = nil }
        while !Task.isCancelled {
            if intervalGeneration != generation {
                generation = intervalGeneration
                deadline = start.addingTimeInterval(pollingInterval)
                nextFireAt = deadline
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return }
            try? await Task.sleep(for: .seconds(min(remaining, 1.0)))
        }
    }

    func resetSteadyState() {
        cachedPlanTier = .unknown
        cachedAutoTopUp = nil
        lastMetadataRefreshAt = nil
        metadataRefreshInterval = 6 * 3600
    }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) {
        switch level {
        case .warning:
            metadataRefreshInterval = max(metadataRefreshInterval, 12 * 3600)
        case .critical:
            metadataRefreshInterval = max(metadataRefreshInterval, 24 * 3600)
        }
    }

    func fetchUsage(forceMetadataRefresh: Bool = false) async {
        do {
            let usageData = try await fetchUsageData(forceMetadataRefresh: forceMetadataRefresh)
            onUsageUpdate?(usageData)
        } catch {
            onError?(error)
        }
    }

    private func fetchUsageData(forceMetadataRefresh: Bool) async throws -> CodexUsageData {
        let shouldRefreshMetadata = forceMetadataRefresh || metadataIsStale()
        async let snapshotTask = apiClient.fetchUsageSnapshot(includeMetadataEndpoints: shouldRefreshMetadata)
        async let profileTask: OpenAIMeProfile? = shouldRefreshMetadata ? try? await apiClient.fetchMeProfile(forceRefresh: forceMetadataRefresh) : nil
        async let autoTopUpTask: OpenAIAutoTopUpSettings? = shouldRefreshMetadata ? try? await apiClient.fetchAutoTopUpSettings() : nil

        let snapshot = try await snapshotTask
        let profile = await profileTask
        if let refreshed = await autoTopUpTask {
            cachedAutoTopUp = refreshed
        }
        let autoTopUp = cachedAutoTopUp
        let billing = snapshot.billing

        let planLabel = profile?.planLabel ?? snapshot.planLabel
        let planTier = resolvePlanTier(from: planLabel, refreshedMetadata: shouldRefreshMetadata)
        let slots = mapLimitsToSlots(snapshot.limits)

        return CodexUsageData(
            fiveHourUtilization: slots.first?.utilization,
            fiveHourResetsAt: slots.first?.resetsAt,
            sevenDayUtilization: slots.second?.utilization,
            sevenDayResetsAt: slots.second?.resetsAt,
            sevenDayOpusUtilization: slots.third?.utilization,
            sevenDayOpusResetsAt: slots.third?.resetsAt,
            sevenDayOpusName: displayName(for: slots.third),
            sevenDaySonnetUtilization: slots.fourth?.utilization,
            sevenDaySonnetResetsAt: slots.fourth?.resetsAt,
            sevenDaySonnetName: displayName(for: slots.fourth),
            extraUsageUtilization: slots.fifth?.utilization,
            extraUsageResetsAt: slots.fifth?.resetsAt,
            extraUsageName: displayName(for: slots.fifth),
            planTier: planTier,
            prepaidCreditsRemaining: billing.creditBalance.map { Int(($0 * 100).rounded()) },
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: billing.creditBalance == nil ? nil : "USD",
            prepaidAutoReloadEnabled: autoTopUp?.isEnabled,
            // The spend cap comes from the usage payload when the account has one; the
            // auto top-up budget is the fallback.
            overageMonthlyLimit: (billing.spendLimit ?? autoTopUp?.monthlyLimit)
                .map { Int(($0 * 100).rounded()) },
            overageUsedCredits: Self.spentCredits(autoTopUp),
            overageCurrency: (billing.spendLimit ?? autoTopUp?.monthlyLimit) == nil ? nil : "USD",
            overageEnabled: autoTopUp?.isEnabled,
            overageOutOfCredits: billing.overageLimitReached ?? billing.spendLimitReached
        )
    }

    /// Spent = budget minus what is left, in minor units; nil unless both are reported.
    private static func spentCredits(_ settings: OpenAIAutoTopUpSettings?) -> Int? {
        guard let limit = settings?.monthlyLimit, let remaining = settings?.monthlyRemaining else {
            return nil
        }
        return Int((max(limit - remaining, 0) * 100).rounded())
    }

    private func metadataIsStale() -> Bool {
        guard let lastMetadataRefreshAt else { return true }
        return Date().timeIntervalSince(lastMetadataRefreshAt) >= metadataRefreshInterval
    }

    private func resolvePlanTier(from planLabel: String?, refreshedMetadata: Bool) -> CodexPlanTier {
        let resolved = determinePlanTier(from: planLabel)
        if resolved != .unknown {
            cachedPlanTier = resolved
            if refreshedMetadata {
                lastMetadataRefreshAt = Date()
            }
            return resolved
        }

        if refreshedMetadata {
            lastMetadataRefreshAt = Date()
        }
        return cachedPlanTier
    }

    func mapLimitsToSlots(_ limits: [OpenAIUsageLimit]) -> (
        first: OpenAIUsageLimit?,
        second: OpenAIUsageLimit?,
        third: OpenAIUsageLimit?,
        fourth: OpenAIUsageLimit?,
        fifth: OpenAIUsageLimit?
    ) {
        if limits.isEmpty {
            return (nil, nil, nil, nil, nil)
        }

        var remaining = limits
        var slots: [OpenAIUsageLimit?] = Array(repeating: nil, count: 5)

        let fixedNameToSlot: [(name: String, slotIndex: Int)] = [
            ("primary_window", 0),
            ("secondary_window", 1),
            ("weekly_window", 1),
            ("tertiary_window", 2),
            ("quaternary_window", 3)
        ]

        for fixedLimit in fixedNameToSlot where slots[fixedLimit.slotIndex] == nil {
            slots[fixedLimit.slotIndex] = popFirst(from: &remaining) {
                normalizedName(of: $0) == fixedLimit.name
                    && isCompatibleWithSlot($0, slotIndex: fixedLimit.slotIndex)
            }
        }

        if slots[0] == nil {
            slots[0] = popBest(from: &remaining, minimumScore: 1, scoring: fiveHourScore)
        }
        if slots[1] == nil {
            slots[1] = popBest(from: &remaining, minimumScore: 1, scoring: sevenDayScore)
        }

        // Keep Code Review as the dedicated "extra" card when present.
        if slots[4] == nil {
            slots[4] = popBest(from: &remaining, minimumScore: 120, scoring: codeReviewScore)
        }

        // Remaining model/window buckets fill the two middle cards.
        if slots[2] == nil {
            slots[2] = popBest(from: &remaining, minimumScore: 1, scoring: modelFiveHourScore)
        }
        if slots[3] == nil {
            slots[3] = popBest(from: &remaining, minimumScore: 1, scoring: modelWeeklyScore)
        }

        let sortedRemainder = remaining.sorted(by: compareLimitOrder)
        var remainderIndex = 0
        for slotIndex in 0 ..< slots.count where slots[slotIndex] == nil {
            guard remainderIndex < sortedRemainder.count else { break }
            slots[slotIndex] = sortedRemainder[remainderIndex]
            remainderIndex += 1
        }

        return (slots[0], slots[1], slots[2], slots[3], slots[4])
    }

    private func popFirst(
        from limits: inout [OpenAIUsageLimit],
        where predicate: (OpenAIUsageLimit) -> Bool
    ) -> OpenAIUsageLimit? {
        guard let index = limits.firstIndex(where: predicate) else { return nil }
        return limits.remove(at: index)
    }

    private func popBest(
        from limits: inout [OpenAIUsageLimit],
        minimumScore: Int,
        scoring: (OpenAIUsageLimit) -> Int
    ) -> OpenAIUsageLimit? {
        guard !limits.isEmpty else { return nil }

        var bestIndex: Int?
        var bestScore = Int.min

        for (index, limit) in limits.enumerated() {
            let score = scoring(limit)
            guard score >= minimumScore else { continue }

            if let currentBestIndex = bestIndex {
                let currentBest = limits[currentBestIndex]
                if score > bestScore || (score == bestScore && compareLimitOrder(limit, currentBest)) {
                    bestIndex = index
                    bestScore = score
                }
            } else {
                bestIndex = index
                bestScore = score
            }
        }

        guard let bestIndex else { return nil }
        return limits.remove(at: bestIndex)
    }

    private func fiveHourScore(_ limit: OpenAIUsageLimit) -> Int {
        guard isPlausibleFiveHourWindow(limit) else { return .min }

        let normalized = normalizedName(of: limit)
        var score = 0

        if normalized == "primary_window" { score += 220 }
        if containsAny(in: normalized, keywords: ["5h", "5_hour", "5hr", "five_hour", "hourly"]) { score += 180 }
        if containsAny(in: normalized, keywords: ["hour", "hours"]) { score += 80 }
        if containsAny(in: normalized, keywords: ["day", "week", "weekly"]) { score -= 90 }

        if let hours = hoursUntilReset(for: limit) {
            if hours > 0, hours <= 12 {
                score += 120
            } else if hours > 12, hours <= 36 {
                score += 20
            } else if hours > 36 {
                score -= 80
            }
        }

        return score
    }

    private func sevenDayScore(_ limit: OpenAIUsageLimit) -> Int {
        guard isPlausibleWeeklyWindow(limit) else { return .min }

        let normalized = normalizedName(of: limit)
        var score = 0

        if normalized == "secondary_window" || normalized == "weekly_window" { score += 220 }
        if containsAny(in: normalized, keywords: ["7d", "7_day", "seven_day", "weekly", "week"]) { score += 180 }
        if containsAny(in: normalized, keywords: ["hour", "hours"]) { score -= 90 }

        if let hours = hoursUntilReset(for: limit) {
            if hours >= 24, hours <= 240 {
                score += 120
            } else if hours > 0, hours < 16 {
                score -= 80
            } else if hours > 240 {
                score -= 20
            }
        }

        return score
    }

    private func codeReviewScore(_ limit: OpenAIUsageLimit) -> Int {
        let normalized = normalizedName(of: limit)
        let tokens = tokenSet(of: limit)
        var score = 0

        if containsAny(in: normalized, keywords: ["code_review", "review_code", "codereview"]) {
            score += 260
        }
        if tokens.contains("review") || tokens.contains("revisar") {
            score += 120
        }
        if tokens.contains("code") || tokens.contains("codigo") || tokens.contains("codex") {
            score += 100
        }
        if tokens.contains("spark") {
            score -= 80
        }
        if containsAny(in: normalized, keywords: ["5h", "5_hour", "hourly", "7d", "7_day", "weekly"]) {
            score -= 20
        }

        return score
    }

    private func modelFiveHourScore(_ limit: OpenAIUsageLimit) -> Int {
        guard isPlausibleFiveHourWindow(limit) else { return .min }

        let normalized = normalizedName(of: limit)
        let tokens = tokenSet(of: limit)
        var score = 0

        if containsAny(in: normalized, keywords: ["5h", "5_hour", "5hr", "five_hour", "hourly"]) { score += 180 }
        if containsAny(in: normalized, keywords: ["hour", "hours"]) { score += 70 }
        if tokens.contains("spark") || tokens.contains("gpt") || tokens.contains("codex") { score += 40 }
        if codeReviewScore(limit) >= 120 { score -= 200 }
        if containsAny(in: normalized, keywords: ["7d", "7_day", "seven_day", "weekly", "week"]) { score -= 80 }

        if let hours = hoursUntilReset(for: limit) {
            if hours > 0, hours <= 12 {
                score += 100
            } else if hours > 12, hours <= 36 {
                score += 30
            } else if hours > 36 {
                score -= 60
            }
        }

        return score
    }

    private func modelWeeklyScore(_ limit: OpenAIUsageLimit) -> Int {
        guard isPlausibleWeeklyWindow(limit) else { return .min }

        let normalized = normalizedName(of: limit)
        let tokens = tokenSet(of: limit)
        var score = 0

        if containsAny(in: normalized, keywords: ["7d", "7_day", "seven_day", "weekly", "week"]) { score += 180 }
        if tokens.contains("spark") || tokens.contains("gpt") || tokens.contains("codex") { score += 40 }
        if codeReviewScore(limit) >= 120 { score -= 200 }
        if containsAny(in: normalized, keywords: ["5h", "5_hour", "5hr", "hourly", "hour"]) { score -= 80 }

        if let hours = hoursUntilReset(for: limit) {
            if hours >= 24, hours <= 240 {
                score += 100
            } else if hours > 0, hours < 16 {
                score -= 80
            }
        }

        return score
    }

    private func hoursUntilReset(for limit: OpenAIUsageLimit) -> Double? {
        guard let resetsAt = limit.resetsAt else { return nil }
        return resetsAt.timeIntervalSinceNow / 3600
    }

    private func isCompatibleWithSlot(_ limit: OpenAIUsageLimit, slotIndex: Int) -> Bool {
        switch slotIndex {
        case 0, 2:
            return isPlausibleFiveHourWindow(limit)
        case 1, 3:
            return isPlausibleWeeklyWindow(limit)
        default:
            return true
        }
    }

    private func isPlausibleFiveHourWindow(_ limit: OpenAIUsageLimit) -> Bool {
        guard let hours = hoursUntilReset(for: limit) else { return true }
        // Allow a small clock skew around reset, but never call a multi-day limit "5-hour".
        return hours >= -0.25 && hours <= 12
    }

    private func isPlausibleWeeklyWindow(_ limit: OpenAIUsageLimit) -> Bool {
        guard let hours = hoursUntilReset(for: limit) else { return true }
        return hours >= 12 && hours <= 240
    }

    private func normalizedName(of limit: OpenAIUsageLimit) -> String {
        let normalized = limit.name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = normalized.split { !$0.isLetter && !$0.isNumber }
        return tokens.joined(separator: "_")
    }

    private func tokenSet(of limit: OpenAIUsageLimit) -> Set<String> {
        Set(normalizedName(of: limit).split(separator: "_").map(String.init))
    }

    private func containsAny(in value: String, keywords: [String]) -> Bool {
        keywords.contains(where: value.contains)
    }

    private func hasMeaningfulDisplayName(_ limit: OpenAIUsageLimit) -> Bool {
        displayName(for: limit) != nil
    }

    private func compareLimitOrder(_ lhs: OpenAIUsageLimit, _ rhs: OpenAIUsageLimit) -> Bool {
        let lhsMeaningful = hasMeaningfulDisplayName(lhs)
        let rhsMeaningful = hasMeaningfulDisplayName(rhs)
        if lhsMeaningful != rhsMeaningful {
            return lhsMeaningful && !rhsMeaningful
        }

        switch (lhs.resetsAt, rhs.resetsAt) {
        case let (l?, r?):
            if l != r { return l < r }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func displayName(for limit: OpenAIUsageLimit?) -> String? {
        guard let raw = limit?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let lowercased = raw.lowercased()
        let normalized = lowercased.replacingOccurrences(of: "-", with: "_")
        let genericNames = ["usage", "limit", "limits", "quota", "quotas", "data", "item", "items"]
        if genericNames.contains(lowercased) {
            return nil
        }

        // Hide backend/internal window identifiers so the UI uses friendlier fallbacks.
        if [
            "primary_window",
            "secondary_window",
            "tertiary_window",
            "quaternary_window",
            "weekly_window"
        ].contains(normalized) {
            return nil
        }

        if normalized == "code_review" || normalized == "review_code" || normalized == "codereview" {
            return String(localized: "Code Review")
        }

        return raw
    }

    private func determinePlanTier(from planLabel: String?) -> CodexPlanTier {
        guard let planLabel else { return .unknown }
        let tier = planLabel.lowercased()
        if tier.contains("enterprise") { return .enterprise }
        if tier.contains("team") || tier.contains("business") { return .team }
        if tier.contains("pro") || tier.contains("plus") { return .pro }
        if tier.contains("max") { return .max }
        if tier.contains("free") { return .free }
        return .unknown
    }
}
