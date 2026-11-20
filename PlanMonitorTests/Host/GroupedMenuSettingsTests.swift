import Foundation
import Testing
@testable import PlanMonitor

/// Settings › Grouped menu: the two text sizes and the providers' order, and that each persists
/// only once chosen.
@Suite("Grouped menu settings")
@MainActor
struct GroupedMenuSettingsTests {

    // MARK: - Sizes

    @Test func theFourStepsAreTheUsersPoints() {
        #expect(GroupedTextSize.allCases.map(\.points) == [9, 11, 15, 18])
    }

    // MARK: - Order

    @Test func nothingStoredIsTodaysOrder() {
        #expect(GroupedMenuOrder.repaired(nil) == ProviderID.allCases)
        #expect(GroupedMenuOrder.repaired([]) == ProviderID.allCases)
    }

    @Test func aStoredOrderIsKept() {
        let custom: [ProviderID] = [.codex, .opencode, .claude, .claudeapi, .grok, .openrouter]
        #expect(GroupedMenuOrder.repaired(custom.map(\.rawValue)) == custom)
    }

    @Test func aProviderMissingFromStorageLandsLast() {
        let stored = ["codex", "claude", "grok", "openrouter", "claudeapi"]
        #expect(GroupedMenuOrder.repaired(stored) == [.codex, .claude, .grok, .openrouter, .claudeapi, .opencode])
    }

    @Test func unknownAndRepeatedIdsAreSkipped() {
        let stored = ["codex", "someday", "codex", "claude"]
        let repaired = GroupedMenuOrder.repaired(stored)
        #expect(repaired.prefix(2) == [.codex, .claude])
        #expect(repaired.count == ProviderID.allCases.count)
        #expect(Set(repaired) == Set(ProviderID.allCases))
    }

    @Test func enabledProvidersFollowTheUsersOrder() {
        let order: [ProviderID] = [.codex, .claude, .grok, .openrouter, .claudeapi, .opencode]
        #expect(GroupedMenuOrder.sorted([.claude, .codex, .openrouter], by: order) == [.codex, .claude, .openrouter])
        #expect(GroupedMenuOrder.sorted([.openrouter, .claudeapi], by: [.claudeapi, .openrouter]) == [.claudeapi, .openrouter])
    }

    // MARK: - Persistence

    @Test func defaultsAreRegularAndTodaysOrderAndNothingIsWritten() {
        withDefaults { defaults in
            let preferences = GlobalPreferences(defaults: defaults, readLoginItem: false)
            #expect(preferences.groupedTitleSize == .regular)
            #expect(preferences.groupedAmountSize == .regular)
            #expect(preferences.groupedOrder == ProviderID.allCases)
            #expect(defaults.object(forKey: "groupedMenu.titleSize") == nil)
            #expect(defaults.object(forKey: "groupedMenu.amountSize") == nil)
            #expect(defaults.object(forKey: "groupedMenu.order") == nil)
        }
    }

    @Test func choicesSurviveARelaunch() {
        withDefaults { defaults in
            let first = GlobalPreferences(defaults: defaults, readLoginItem: false)
            first.groupedTitleSize = .huge
            first.groupedAmountSize = .big
            first.groupedOrder = [.codex, .claude, .grok, .openrouter, .claudeapi, .opencode]

            let second = GlobalPreferences(defaults: defaults, readLoginItem: false)
            #expect(second.groupedTitleSize == .huge)
            #expect(second.groupedAmountSize == .big)
            #expect(second.groupedOrder == [.codex, .claude, .grok, .openrouter, .claudeapi, .opencode])
        }
    }
}
