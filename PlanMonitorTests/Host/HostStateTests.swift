import Foundation
import SwiftUI
import Testing
@testable import PlanTracker

@MainActor
struct HostStateTests {
    @Test func absentProviderPreferenceDefaultsToClaudeOnly() {
        withDefaults { defaults in
            let providers = EnabledProviders(defaults: defaults)

            #expect(providers.values == [.claude])
            #expect(defaults.stringArray(forKey: "enabledProviders") == ["claude"])
        }
    }

    @Test func unknownProviderIDsAreFilteredWithoutLosingKnownValues() {
        withDefaults { defaults in
            defaults.set(["future-provider", "grok", "claude"], forKey: "enabledProviders")

            let providers = EnabledProviders(defaults: defaults)

            // In memory only the ids this build knows are enabled…
            #expect(providers.values == [.claude, .grok])
            // …but the stored array is left alone so a newer build's value is not destroyed.
            #expect(defaults.stringArray(forKey: "enabledProviders") == ["future-provider", "grok", "claude"])
        }
    }

    @Test func knownButNonCanonicalOrderIsRewrittenCanonically() {
        withDefaults { defaults in
            defaults.set(["grok", "claude"], forKey: "enabledProviders")

            let providers = EnabledProviders(defaults: defaults)

            #expect(providers.values == [.claude, .grok])
            #expect(defaults.stringArray(forKey: "enabledProviders") == ["claude", "grok"])
        }
    }

    @Test func emptyOrEntirelyUnknownProviderSetsRepairToClaude() {
        withDefaults { defaults in
            defaults.set(["future-provider"], forKey: "enabledProviders")
            let providers = EnabledProviders(defaults: defaults)

            #expect(providers.values == [.claude])
            #expect(defaults.stringArray(forKey: "enabledProviders") == ["claude"])
        }
    }

    @Test func emptyArrayRepairsToClaude() {
        withDefaults { defaults in
            defaults.set([String](), forKey: "enabledProviders")
            let providers = EnabledProviders(defaults: defaults)

            #expect(providers.values == [.claude])
            #expect(defaults.stringArray(forKey: "enabledProviders") == ["claude"])
        }
    }

    @Test func lastEnabledProviderCannotBeDisabled() {
        withDefaults { defaults in
            let providers = EnabledProviders(defaults: defaults)
            providers.set(.claude, enabled: false)
            #expect(providers.values == [.claude])

            providers.set(.codex, enabled: true)
            providers.set(.claude, enabled: false)
            #expect(providers.values == [.codex])

            providers.set(.codex, enabled: false)
            #expect(providers.values == [.codex])
        }
    }

    @Test func bindingCannotDisableTheLastProvider() {
        withDefaults { defaults in
            let providers = EnabledProviders(defaults: defaults)
            let claude = providers.binding(for: .claude)

            #expect(claude.wrappedValue == true)
            claude.wrappedValue = false
            #expect(claude.wrappedValue == true)
            #expect(providers.values == [.claude])
            #expect(defaults.stringArray(forKey: "enabledProviders") == ["claude"])

            let codex = providers.binding(for: .codex)
            codex.wrappedValue = true
            claude.wrappedValue = false
            #expect(providers.values == [.codex])
            #expect(claude.wrappedValue == false)
        }
    }

    @Test func providerPersistenceOrderIsStable() {
        withDefaults { defaults in
            let providers = EnabledProviders(defaults: defaults)
            providers.set(.openrouter, enabled: true)
            providers.set(.grok, enabled: true)
            providers.set(.codex, enabled: true)

            #expect(
                defaults.stringArray(forKey: "enabledProviders")
                    == ["claude", "codex", "grok", "openrouter"]
            )
        }
    }

    @Test func changesStreamYieldsExactlyOneEventPerRealChange() async {
        await withDefaultsAsync { defaults in
            let providers = EnabledProviders(defaults: defaults)
            var iterator = providers.changes().makeAsyncIterator()

            providers.set(.codex, enabled: true)
            providers.set(.codex, enabled: true) // no-op: already enabled
            providers.set(.claude, enabled: false)
            providers.set(.codex, enabled: false) // rejected: last provider
            providers.set(.grok, enabled: true)

            let first = await iterator.next()
            let second = await iterator.next()
            let third = await iterator.next()

            #expect(first == EnabledProviders.Change(provider: .codex, isEnabled: true))
            #expect(second == EnabledProviders.Change(provider: .claude, isEnabled: false))
            #expect(third == EnabledProviders.Change(provider: .grok, isEnabled: true))
            #expect(providers.values == [.codex, .grok])
        }
    }

    @Test func rejectedDisableYieldsNoChange() async {
        await withDefaultsAsync { defaults in
            let providers = EnabledProviders(defaults: defaults)
            var iterator = providers.changes().makeAsyncIterator()

            providers.set(.claude, enabled: false) // rejected
            providers.set(.openrouter, enabled: true) // the only real change

            let only = await iterator.next()
            #expect(only == EnabledProviders.Change(provider: .openrouter, isEnabled: true))
        }
    }

    @Test func globalPreferencesMigrateAndRepairValues() {
        withDefaults { defaults in
            defaults.set(7, forKey: "pollingIntervalMinutes")
            defaults.set(false, forKey: "showRemainingPercent")
            defaults.set(true, forKey: "trackSessionTime")
            defaults.set(15, forKey: "recentModelsWindow")

            let preferences = GlobalPreferences(defaults: defaults, readLoginItem: false)

            #expect(preferences.pollingIntervalMinutes == 5)
            #expect(preferences.showRemainingPercent == false)
            #expect(defaults.bool(forKey: "claude.trackSessionTime"))
            #expect(defaults.integer(forKey: "openrouter.recentModelsWindow") == 15)
            #expect(defaults.bool(forKey: "trackSessionTime"))
        }
    }

    // MARK: - HostMigration

    @Test func hostMigrationIsIdempotentAndRetainsLegacyKeys() {
        withDefaults { defaults in
            defaults.set(true, forKey: "trackSessionTime")
            defaults.set(4321.5, forKey: "sessionAccumulatedSeconds")
            defaults.set(1_700_000_000.0, forKey: "sessionLastResetDate")
            defaults.set(true, forKey: "appRuntime.didLaunchCleanly")

            HostMigration.run(defaults: defaults)

            #expect(defaults.integer(forKey: HostMigration.markerKey) == 2)
            #expect(defaults.bool(forKey: "claude.trackSessionTime"))
            #expect(defaults.double(forKey: "claude.session.accumulatedSeconds") == 4321.5)
            #expect(defaults.double(forKey: "claude.session.lastResetDate") == 1_700_000_000.0)
            #expect(defaults.bool(forKey: "host.runtime.didLaunchCleanly"))
            // Legacy keys stay for rollback.
            #expect(defaults.bool(forKey: "trackSessionTime"))
            #expect(defaults.double(forKey: "sessionAccumulatedSeconds") == 4321.5)

            // A second run changes nothing, even when the legacy values moved on.
            defaults.set(9999.0, forKey: "sessionAccumulatedSeconds")
            defaults.set(false, forKey: "trackSessionTime")
            HostMigration.run(defaults: defaults)

            #expect(defaults.integer(forKey: HostMigration.markerKey) == 2)
            #expect(defaults.double(forKey: "claude.session.accumulatedSeconds") == 4321.5)
            #expect(defaults.bool(forKey: "claude.trackSessionTime"))
            #expect(defaults.double(forKey: "sessionAccumulatedSeconds") == 9999.0)
            #expect(defaults.bool(forKey: "trackSessionTime") == false)
        }
    }

    @Test func legacyV1MarkerIsTreatedAsVersionOneSoStepTwoStillRuns() {
        withDefaults { defaults in
            defaults.set(true, forKey: "host.comboMigration.v1")
            // Step 1 already ran on this install and the user has since changed the value;
            // step 1 must not run again and overwrite it.
            defaults.set(true, forKey: "trackSessionTime")
            defaults.set(false, forKey: "claude.trackSessionTime")
            // A step-1 key with no namespaced copy: only a re-run of step 1 would create one.
            defaults.set(true, forKey: "showRecentModels")
            defaults.set(777.0, forKey: "sessionAccumulatedSeconds")

            HostMigration.run(defaults: defaults)

            #expect(defaults.integer(forKey: HostMigration.markerKey) == 2)
            #expect(defaults.bool(forKey: "claude.trackSessionTime") == false)
            #expect(defaults.object(forKey: "openrouter.showRecentModels") == nil)
            #expect(defaults.double(forKey: "claude.session.accumulatedSeconds") == 777.0)
        }
    }

    @Test func hostMigrationDoesNotOverwriteExistingNamespacedValues() {
        withDefaults { defaults in
            defaults.set(100.0, forKey: "sessionAccumulatedSeconds")
            defaults.set(250.0, forKey: "claude.session.accumulatedSeconds")

            HostMigration.run(defaults: defaults)

            #expect(defaults.double(forKey: "claude.session.accumulatedSeconds") == 250.0)
        }
    }

    // MARK: - Coordinator

    @Test func coordinatorLifecycleIsProviderLocalAndIdempotent() async {
        let claude = ProviderRuntimeSpy(id: .claude)
        let codex = ProviderRuntimeSpy(id: .codex)
        let coordinator = ProviderRuntimeCoordinator(
            runtimes: [claude, codex],
            observeMemoryPressure: false
        )

        await coordinator.resume(.claude)
        await coordinator.resume(.claude)
        await coordinator.refresh(.codex)
        await coordinator.refresh(.claude)
        await coordinator.handleMemoryPressure(.warning)
        await coordinator.suspend(.codex)
        await coordinator.suspend(.claude)
        await coordinator.suspend(.claude)

        #expect(claude.enableCount == 1)
        #expect(claude.refreshCount == 1)
        #expect(claude.memoryPressureCount == 1)
        #expect(claude.disableCount == 1)
        #expect(codex.enableCount == 0)
        #expect(codex.refreshCount == 0)
        #expect(codex.memoryPressureCount == 0)
        #expect(codex.disableCount == 0)
    }

    @Test func startResumesOnlyEnabledProvidersInStableOrder() async {
        await withDefaultsAsync { defaults in
            defaults.set(["openrouter", "grok", "claude"], forKey: "enabledProviders")
            let providers = EnabledProviders(defaults: defaults)

            let log = ProviderRuntimeLog()
            let spies = ProviderID.allCases.map { ProviderRuntimeSpy(id: $0, log: log) }
            let coordinator = ProviderRuntimeCoordinator(runtimes: spies, observeMemoryPressure: false)

            coordinator.start(observing: providers)
            let settled = await waitUntil { log.enabled.count == 3 }

            #expect(settled)
            #expect(log.enabled == [.claude, .grok, .openrouter])
            #expect(spies.first { $0.providerID == .codex }?.enableCount == 0)
            #expect(coordinator.isActive(.claude))
            #expect(coordinator.isActive(.grok))
            #expect(coordinator.isActive(.openrouter))
            #expect(!coordinator.isActive(.codex))

            // Calling start again is a no-op.
            coordinator.start(observing: providers)
            try? await Task.sleep(for: .milliseconds(50))
            #expect(log.enabled.count == 3)

            await coordinator.stopAll()
            #expect(log.disabled == [.claude, .grok, .openrouter])
        }
    }

    @Test func startFollowsEnablementChanges() async {
        await withDefaultsAsync { defaults in
            let providers = EnabledProviders(defaults: defaults)
            let log = ProviderRuntimeLog()
            let spies = ProviderID.allCases.map { ProviderRuntimeSpy(id: $0, log: log) }
            let coordinator = ProviderRuntimeCoordinator(runtimes: spies, observeMemoryPressure: false)

            coordinator.start(observing: providers)
            let claudeStarted = await waitUntil { log.enabled == [.claude] }
            #expect(claudeStarted)

            providers.set(.codex, enabled: true)
            let codexStarted = await waitUntil { log.enabled == [.claude, .codex] }
            #expect(codexStarted)

            providers.set(.claude, enabled: false)
            let claudeStopped = await waitUntil { log.disabled == [.claude] }
            #expect(claudeStopped)
            #expect(!coordinator.isActive(.claude))
            #expect(coordinator.isActive(.codex))

            await coordinator.stopAll()
        }
    }

    @Test func slowEnableOnOneProviderDoesNotDelayAnother() async {
        await withDefaultsAsync { defaults in
            defaults.set(["claude", "codex"], forKey: "enabledProviders")
            let providers = EnabledProviders(defaults: defaults)

            let log = ProviderRuntimeLog()
            let claude = ProviderRuntimeSpy(id: .claude, enableDelay: .milliseconds(400), log: log)
            let codex = ProviderRuntimeSpy(id: .codex, log: log)
            let coordinator = ProviderRuntimeCoordinator(runtimes: [claude, codex], observeMemoryPressure: false)

            let clock = ContinuousClock()
            let started = clock.now
            coordinator.start(observing: providers)

            let codexEnabled = await waitUntil { codex.enableCount == 1 }
            let codexLatency = clock.now - started

            #expect(codexEnabled)
            #expect(codexLatency < .milliseconds(300))
            #expect(claude.enableCount == 0)
            #expect(coordinator.isActive(.codex))
            #expect(!coordinator.isActive(.claude))

            let claudeEnabled = await waitUntil { claude.enableCount == 1 }
            #expect(claudeEnabled)
            #expect(log.enabled == [.codex, .claude])

            await coordinator.stopAll()
        }
    }
}
