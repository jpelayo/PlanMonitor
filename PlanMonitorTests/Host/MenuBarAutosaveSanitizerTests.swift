import Foundation
import Testing
@testable import PlanTracker

/// The sanitiser runs before any status item exists, on every launch. It must remove exactly the
/// bookkeeping that keeps an item off the bar — and nothing the user arranged themselves.
struct MenuBarAutosaveSanitizerTests {
    private let names = ["PlanTracker.claude", "PlanTracker.codex"]
    private let screen: CGFloat = 2560

    @Test func negativePositionIsRemoved() {
        withDefaults { defaults in
            defaults.set(-40.0, forKey: "NSStatusItem Preferred Position PlanTracker.claude")
            let removed = MenuBarAutosaveSanitizer.sanitise(defaults, autosaveNames: names, widestScreen: screen)
            #expect(removed == ["NSStatusItem Preferred Position PlanTracker.claude"])
            #expect(defaults.object(forKey: "NSStatusItem Preferred Position PlanTracker.claude") == nil)
        }
    }

    @Test func positionBeyondTheWidestScreenIsRemoved() {
        withDefaults { defaults in
            defaults.set(10_000.0, forKey: "NSStatusItem Preferred Position PlanTracker.codex")
            let removed = MenuBarAutosaveSanitizer.sanitise(defaults, autosaveNames: names, widestScreen: screen)
            #expect(removed == ["NSStatusItem Preferred Position PlanTracker.codex"])
        }
    }

    /// The user's own arrangement is exactly what must survive every launch.
    @Test func sanePositionIsKept() {
        withDefaults { defaults in
            defaults.set(317.0, forKey: "NSStatusItem Preferred Position PlanTracker.claude")
            let removed = MenuBarAutosaveSanitizer.sanitise(defaults, autosaveNames: names, widestScreen: screen)
            #expect(removed.isEmpty)
            #expect(defaults.double(forKey: "NSStatusItem Preferred Position PlanTracker.claude") == 317)
        }
    }

    @Test func hiddenVisibilityIsRemovedAndVisibleIsKept() {
        withDefaults { defaults in
            defaults.set(false, forKey: "NSStatusItem Visible PlanTracker.claude")
            defaults.set(false, forKey: "NSStatusItem VisibleCC PlanTracker.codex")
            defaults.set(true, forKey: "NSStatusItem VisibleCC PlanTracker.claude")
            let removed = MenuBarAutosaveSanitizer.sanitise(defaults, autosaveNames: names, widestScreen: screen)
            #expect(removed == [
                "NSStatusItem Visible PlanTracker.claude",
                "NSStatusItem VisibleCC PlanTracker.codex"
            ])
            #expect(defaults.bool(forKey: "NSStatusItem VisibleCC PlanTracker.claude") == true)
        }
    }

    /// `Item-<n>` is the auto-name from the instant before the app names an item; whatever
    /// was persisted under it was written then, never by us.
    @Test func everyAutoNamedKeyIsRemoved() {
        withDefaults { defaults in
            defaults.set(12.0, forKey: "NSStatusItem Preferred Position Item-0")
            defaults.set(false, forKey: "NSStatusItem Visible Item-1")
            defaults.set(true, forKey: "NSStatusItem VisibleCC Item-12")
            let removed = MenuBarAutosaveSanitizer.sanitise(defaults, autosaveNames: names, widestScreen: screen)
            #expect(removed == [
                "NSStatusItem Preferred Position Item-0",
                "NSStatusItem Visible Item-1",
                "NSStatusItem VisibleCC Item-12"
            ])
        }
    }

    @Test func unrelatedKeysAreUntouched() {
        withDefaults { defaults in
            defaults.set("week", forKey: "claude.menuBarRingSource")
            defaults.set(5, forKey: "pollingIntervalMinutes")
            defaults.set(true, forKey: "NSStatusItem VisibleCC Battery")   // not one of ours, not auto-named
            let removed = MenuBarAutosaveSanitizer.sanitise(defaults, autosaveNames: names, widestScreen: screen)
            #expect(removed.isEmpty)
            #expect(defaults.string(forKey: "claude.menuBarRingSource") == "week")
            #expect(defaults.integer(forKey: "pollingIntervalMinutes") == 5)
            #expect(defaults.bool(forKey: "NSStatusItem VisibleCC Battery") == true)
        }
    }

    @Test func nothingToDoReturnsNothing() {
        withDefaults { defaults in
            #expect(MenuBarAutosaveSanitizer.sanitise(defaults, autosaveNames: names, widestScreen: screen).isEmpty)
        }
    }
}
