//
//  CodexUsageMappingTests.swift
//  PlanTrackerTests
//
//  Copyright © 2025 Intelligent Computing OU. All rights reserved.
//

import Foundation
import Testing
@testable import PlanTracker

struct CodexUsageMappingTests {

    @Test func primaryWindowWithMultiDayResetMapsToWeeklySlot() async {
        let service = CodexUsagePollingService(apiClient: OpenAIAPIClient())
        let reset = Date().addingTimeInterval(5 * 24 * 60 * 60)

        let slots = await service.mapLimitsToSlots([
            OpenAIUsageLimit(
                name: "primary_window",
                utilization: 48,
                resetsAt: reset
            )
        ])

        #expect(slots.first == nil)
        #expect(slots.second?.utilization == 48)
        #expect(slots.second?.resetsAt == reset)
    }

    @Test func absentFiveHourLimitStaysAbsentWhileOtherLimitsRemainVisible() async {
        let service = CodexUsagePollingService(apiClient: OpenAIAPIClient())
        let weeklyReset = Date().addingTimeInterval(5 * 24 * 60 * 60)
        let reviewReset = Date().addingTimeInterval(2 * 24 * 60 * 60)

        let slots = await service.mapLimitsToSlots([
            OpenAIUsageLimit(name: "weekly_window", utilization: 42, resetsAt: weeklyReset),
            OpenAIUsageLimit(name: "code_review", utilization: 0, resetsAt: reviewReset)
        ])

        #expect(slots.first == nil)
        #expect(slots.second?.name == "weekly_window")
        #expect(slots.second?.utilization == 42)
        #expect(slots.fifth?.name == "code_review")
        #expect(slots.fifth?.utilization == 0)
    }

    /// The reported bug. Time until reset cannot tell a weekly window in its last hours from a
    /// five-hour one, so a 7-day limit about to reset was re-identified as the 5-hour limit and
    /// flipped back afterwards. `limit_window_seconds` says which it is, whatever the clock.
    @Test func weeklyWindowNearItsResetStaysWeekly() async {
        let service = CodexUsagePollingService(apiClient: OpenAIAPIClient())
        let nearlyDue = Date().addingTimeInterval(3 * 60 * 60)

        let slots = await service.mapLimitsToSlots([
            OpenAIUsageLimit(
                name: "secondary_window",
                utilization: 84,
                resetsAt: nearlyDue,
                windowSeconds: 604_800
            )
        ])

        #expect(slots.first == nil)
        #expect(slots.second?.utilization == 84)
    }

    /// The mirror case: a five-hour window with a long way to run is still five-hour.
    @Test func fiveHourWindowFarFromResetStaysFiveHour() async {
        let service = CodexUsagePollingService(apiClient: OpenAIAPIClient())
        let farOff = Date().addingTimeInterval(4.9 * 60 * 60)

        let slots = await service.mapLimitsToSlots([
            OpenAIUsageLimit(
                name: "primary_window",
                utilization: 12,
                resetsAt: farOff,
                windowSeconds: 18_000
            )
        ])

        #expect(slots.first?.utilization == 12)
        #expect(slots.second == nil)
    }

    /// Both windows of a pair land in their own slots even when their resets are close together.
    @Test func statedWindowLengthsSeparateThePair() async {
        let service = CodexUsagePollingService(apiClient: OpenAIAPIClient())
        let soon = Date().addingTimeInterval(4 * 60 * 60)

        let slots = await service.mapLimitsToSlots([
            OpenAIUsageLimit(name: "secondary_window", utilization: 84, resetsAt: soon, windowSeconds: 604_800),
            OpenAIUsageLimit(name: "primary_window", utilization: 0, resetsAt: soon, windowSeconds: 18_000)
        ])

        #expect(slots.first?.name == "primary_window")
        #expect(slots.second?.name == "secondary_window")
    }

    /// Without a stated length the old reset-clock heuristic still applies — it is the fallback,
    /// not the rule.
    @Test func windowsWithoutAStatedLengthStillUseTheResetClock() async {
        let service = CodexUsagePollingService(apiClient: OpenAIAPIClient())

        let slots = await service.mapLimitsToSlots([
            OpenAIUsageLimit(name: "primary_window", utilization: 7, resetsAt: Date().addingTimeInterval(2 * 60 * 60))
        ])

        #expect(slots.first?.utilization == 7)
    }
}
