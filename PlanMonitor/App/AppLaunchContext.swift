import Foundation

/// How this process was started. Decided once, before any provider state exists, so the
/// composition root can pick real or in-memory backends without consulting the environment
/// again later.
nonisolated struct AppLaunchContext: Sendable {
    /// The unit-test bundle is injected into this app as its host. Nothing that touches the
    /// user's Keychain, login item, or defaults may run in that process.
    let isTestHost: Bool
    /// `-uitesting`: deterministic in-memory backends, no real credentials.
    let isUITest: Bool
    /// `-demo`: reviewer mode from launch.
    let isDemo: Bool

    /// Anything that must never reach the user's real Keychain or preferences.
    var isIsolated: Bool { isTestHost || isUITest }

    static let current: AppLaunchContext = {
        let process = ProcessInfo.processInfo
        let environment = process.environment
        let arguments = process.arguments
        return AppLaunchContext(
            isTestHost: environment["XCTestConfigurationFilePath"] != nil
                || environment["XCTestBundlePath"] != nil
                || environment["XCTestSessionIdentifier"] != nil,
            isUITest: arguments.contains("-uitesting"),
            isDemo: arguments.contains("-demo")
        )
    }()

    init(isTestHost: Bool, isUITest: Bool, isDemo: Bool) {
        self.isTestHost = isTestHost
        self.isUITest = isUITest
        self.isDemo = isDemo
    }
}
