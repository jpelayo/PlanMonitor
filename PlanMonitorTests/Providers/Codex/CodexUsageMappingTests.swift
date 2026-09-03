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

}
