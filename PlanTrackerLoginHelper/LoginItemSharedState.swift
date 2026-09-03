import Foundation

enum LoginItemConfiguration {
    static let mainAppBundleIdentifier = "com.infinitecontext.plantracker"
    static let appGroupIdentifier = "group.com.infinitecontext.plantracker"
}

enum LoginItemSharedState {
    private static let helperEnabledKey = "loginItem.helperEnabled"
    private static let userInitiatedTerminationKey = "loginItem.userInitiatedTermination"
    private static let lastLaunchTimestampKey = "loginItem.lastLaunchTimestamp"
    private static let lastRelaunchTimestampKey = "loginItem.lastRelaunchTimestamp"

    static let defaults = UserDefaults(suiteName: LoginItemConfiguration.appGroupIdentifier) ?? .standard

    static func beginHelperSession() {
        defaults.set(false, forKey: userInitiatedTerminationKey)
    }

    static func isHelperEnabled() -> Bool {
        defaults.object(forKey: helperEnabledKey) as? Bool ?? false
    }

    static func wasUserInitiatedTermination() -> Bool {
        defaults.object(forKey: userInitiatedTerminationKey) as? Bool ?? false
    }

    static func shouldRelaunchMainApp(
        now: Date = Date(),
        minimumRuntime: TimeInterval = 20,
        relaunchCooldown: TimeInterval = 20
    ) -> Bool {
        guard isHelperEnabled() else { return false }
        guard !wasUserInitiatedTermination() else { return false }

        let nowTimestamp = now.timeIntervalSince1970
        if let lastLaunchTimestamp = defaults.object(forKey: lastLaunchTimestampKey) as? TimeInterval,
           nowTimestamp - lastLaunchTimestamp < minimumRuntime {
            return false
        }

        if let lastRelaunchTimestamp = defaults.object(forKey: lastRelaunchTimestampKey) as? TimeInterval,
           nowTimestamp - lastRelaunchTimestamp < relaunchCooldown {
            return false
        }

        return true
    }

    static func recordRelaunchAttempt(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: lastRelaunchTimestampKey)
    }
}
