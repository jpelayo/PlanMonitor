import Foundation

/// A `UserDefaults` suite that exists only for the duration of one test body. Every suite
/// name is unique, so parallel tests never observe each other's keys, and the persistent
/// domain is removed afterwards so nothing leaks into the host app's preferences.
enum TestDefaults {
    static func make() -> (defaults: UserDefaults, suite: String) {
        let suite = "PlanTrackerTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    static func tearDown(_ defaults: UserDefaults, suite: String) {
        defaults.removePersistentDomain(forName: suite)
    }
}

/// Runs `body` with an isolated `UserDefaults` and cleans up afterwards.
func withDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    let (defaults, suite) = TestDefaults.make()
    defer { TestDefaults.tearDown(defaults, suite: suite) }
    return try body(defaults)
}

/// Async variant for bodies that await actors or coordinator tasks.
func withDefaultsAsync<T>(_ body: (UserDefaults) async throws -> T) async rethrows -> T {
    let (defaults, suite) = TestDefaults.make()
    defer { TestDefaults.tearDown(defaults, suite: suite) }
    return try await body(defaults)
}
