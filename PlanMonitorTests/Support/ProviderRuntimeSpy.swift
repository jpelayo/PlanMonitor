import Foundation
@testable import PlanTracker

/// Records the order in which spies were enabled/disabled, shared across the spies of one
/// coordinator so ordering tests can assert on a single timeline.
@MainActor
final class ProviderRuntimeLog {
    private(set) var enabled: [ProviderID] = []
    private(set) var disabled: [ProviderID] = []

    func recordEnabled(_ provider: ProviderID) { enabled.append(provider) }
    func recordDisabled(_ provider: ProviderID) { disabled.append(provider) }
}

/// A `ProviderRuntime` that counts every lifecycle call. `enableDelay` makes `enable()`
/// suspend for that long (without blocking the main actor), and `enableHook` runs at the
/// start of `enable()` for anything else a test needs to inject.
@MainActor
final class ProviderRuntimeSpy: ProviderRuntime {
    let providerID: ProviderID
    var enableCount = 0
    var disableCount = 0
    var refreshCount = 0
    var memoryPressureCount = 0

    var enableDelay: Duration?
    var enableHook: (@MainActor () async -> Void)?
    var log: ProviderRuntimeLog?

    init(id: ProviderID, enableDelay: Duration? = nil, log: ProviderRuntimeLog? = nil) {
        providerID = id
        self.enableDelay = enableDelay
        self.log = log
    }

    func enable() async {
        await enableHook?()
        if let enableDelay {
            try? await Task.sleep(for: enableDelay)
        }
        enableCount += 1
        log?.recordEnabled(providerID)
    }

    func disable() async {
        disableCount += 1
        log?.recordDisabled(providerID)
    }

    func refresh() async { refreshCount += 1 }

    func handleMemoryPressure(_ level: AppMemoryPressureLevel) async {
        memoryPressureCount += 1
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` elapses. Returns whether
/// the condition was met, so callers can `#expect` on it.
@MainActor
@discardableResult
func waitUntil(
    timeout: Duration = .seconds(3),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}
