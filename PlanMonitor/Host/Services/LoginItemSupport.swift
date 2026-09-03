import Foundation
import ServiceManagement

enum LoginItemConfiguration {
    static let helperBundleIdentifier = "com.infinitecontext.plantracker.loginitem"
    static let appGroupIdentifier = "group.com.infinitecontext.plantracker"
}

enum LoginItemSharedState {
    private static let helperEnabledKey = "loginItem.helperEnabled"
    private static let userInitiatedTerminationKey = "loginItem.userInitiatedTermination"
    private static let didLaunchCleanlyKey = "loginItem.didLaunchCleanly"
    private static let lastLaunchTimestampKey = "loginItem.lastLaunchTimestamp"
    private static let lastHeartbeatTimestampKey = "loginItem.lastHeartbeatTimestamp"
    private static let lastRelaunchTimestampKey = "loginItem.lastRelaunchTimestamp"

    static let defaults = UserDefaults(suiteName: LoginItemConfiguration.appGroupIdentifier) ?? .standard

    static func setHelperEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: helperEnabledKey)
    }

    static func isHelperEnabled() -> Bool {
        defaults.object(forKey: helperEnabledKey) as? Bool ?? false
    }

    static func markMainAppLaunch(at date: Date = Date()) {
        defaults.set(false, forKey: userInitiatedTerminationKey)
        defaults.set(false, forKey: didLaunchCleanlyKey)
        defaults.set(date.timeIntervalSince1970, forKey: lastLaunchTimestampKey)
        defaults.set(date.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
    }

    static func markHeartbeat(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
    }

    static func markCleanTermination(at date: Date = Date()) {
        defaults.set(true, forKey: didLaunchCleanlyKey)
        defaults.set(date.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
    }

    static func markUserInitiatedTermination(at date: Date = Date()) {
        defaults.set(true, forKey: userInitiatedTerminationKey)
        defaults.set(true, forKey: didLaunchCleanlyKey)
        defaults.set(date.timeIntervalSince1970, forKey: lastHeartbeatTimestampKey)
    }

    static func beginHelperSession() {
        defaults.set(false, forKey: userInitiatedTerminationKey)
    }

    static func shouldRelaunchMainApp(
        now: Date = Date(),
        minimumRuntime: TimeInterval = 20,
        relaunchCooldown: TimeInterval = 20
    ) -> Bool {
        guard isHelperEnabled() else { return false }
        guard !(defaults.object(forKey: userInitiatedTerminationKey) as? Bool ?? false) else { return false }

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

extension SMAppService.Status {
    /// Only `.enabled` actually launches the helper at login.
    ///
    /// `.requiresApproval` means the item is registered but switched **off** in System
    /// Settings → General → Login Items (or never approved). Reporting that as "on" is what
    /// made the app's toggle disagree with the system: the app said enabled while macOS
    /// would never start it.
    var isEnabledForUI: Bool {
        self == .enabled
    }

    /// Registered, but macOS will not run it until the user approves it.
    var requiresUserApproval: Bool {
        self == .requiresApproval
    }
}
