import AppKit
import Foundation
import Testing
@testable import PlanMonitor

/// The grouped menu-bar item: when it takes effect, what its label is, how its rows write a
/// fraction and a reset, and that the preference behind it persists.
@Suite("Grouped menu-bar item")
@MainActor
struct GroupedMenuTests {

    // MARK: - Rule

    @Test func oneProviderNeverGroups() {
        #expect(!GroupedMenuRule.isEffective(preference: true, enabledCount: 1))
        #expect(!GroupedMenuRule.offersSwitch(enabledCount: 1))
    }

    @Test(arguments: [2, 3, 6])
    func twoOrMoreGroupWhenAsked(_ count: Int) {
        #expect(GroupedMenuRule.isEffective(preference: true, enabledCount: count))
        #expect(GroupedMenuRule.offersSwitch(enabledCount: count))
    }

    @Test func offMeansOff() {
        #expect(!GroupedMenuRule.isEffective(preference: false, enabledCount: 6))
    }

    // MARK: - Preference

    @Test func groupingDefaultsToOffAndIsNotWrittenUntilChosen() {
        withDefaults { defaults in
            let preferences = GlobalPreferences(defaults: defaults, readLoginItem: false)
            #expect(!preferences.groupMenuBarItems)
            #expect(defaults.object(forKey: "groupMenuBarItems") == nil)
        }
    }

    @Test func aChosenGroupingSurvivesARelaunch() {
        withDefaults { defaults in
            GlobalPreferences(defaults: defaults, readLoginItem: false).groupMenuBarItems = true
            #expect(GlobalPreferences(defaults: defaults, readLoginItem: false).groupMenuBarItems)
        }
    }

    // MARK: - Label

    @Test func theLabelIsAPlainRingWithNoText() {
        let label = GroupedMenuBarLabel.make()
        #expect(label.symbolName == "ring.dashed")
        #expect(label.text == nil)
        #expect(label.symbolTint == nil)
        #expect(label.textTint == nil)
        #expect(label.variableValue == nil)
        #expect(label.accessibilityLabel == "PlanMonitor")
    }

    // MARK: - Row

    @Test func fractionsAreClampedAndWrittenWithoutTheLocale() {
        #expect(CompactGaugeRow.percentText(CompactGaugeRow.clamped(1.3)) == "100%")
        #expect(CompactGaugeRow.percentText(CompactGaugeRow.clamped(-0.2)) == "0%")
        #expect(CompactGaugeRow.percentText(CompactGaugeRow.clamped(.nan)) == "0%")
        #expect(CompactGaugeRow.percentText(CompactGaugeRow.clamped(0.426)) == "43%")
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func underAnHourIsMinutes() {
        #expect(CompactGaugeRow.resetText(now.addingTimeInterval(59 * 60 + 30), now: now) == "59m")
        #expect(CompactGaugeRow.resetText(now.addingTimeInterval(20), now: now) == "1m")
    }

    @Test func underADayIsHoursAndMinutes() {
        #expect(CompactGaugeRow.resetText(now.addingTimeInterval(2 * 3600 + 5 * 60), now: now) == "2h 05m")
    }

    @Test func furtherOutIsAWeekdayAndTime() throws {
        let text = try #require(CompactGaugeRow.resetText(now.addingTimeInterval(3 * 24 * 3600), now: now))
        #expect(text.contains(":"))
        #expect(!text.contains("h "))
    }

    @Test func nothingForAPastMissingOrUnstartedWindow() {
        #expect(CompactGaugeRow.resetText(nil, now: now) == nil)
        #expect(CompactGaugeRow.resetText(now.addingTimeInterval(-60), now: now) == nil)
        #expect(CompactGaugeRow.resetText(now.addingTimeInterval(5 * 3600), now: now) == nil)
        #expect(CompactGaugeRow.resetText(now.addingTimeInterval(7 * 24 * 3600), now: now) == nil)
    }
}
