import Foundation

@MainActor
@Observable
final class GlobalPreferences {
    enum Change {
        case pollingInterval(Int)
        case percentageMode(Bool)
        case language(AppLanguage)
    }

    nonisolated static let supportedPollingIntervals = [3, 5, 10, 15, 30, 60]

    var onChange: ((Change) -> Void)?

    var pollingIntervalMinutes: Int {
        didSet {
            let repaired = Self.repairedPollingInterval(pollingIntervalMinutes)
            if repaired != pollingIntervalMinutes {
                pollingIntervalMinutes = repaired
                return
            }
            defaults.set(pollingIntervalMinutes, forKey: Keys.pollingInterval)
            onChange?(.pollingInterval(pollingIntervalMinutes))
        }
    }

    var showRemainingPercent: Bool {
        didSet {
            defaults.set(showRemainingPercent, forKey: Keys.showRemaining)
            onChange?(.percentageMode(showRemainingPercent))
        }
    }

    var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Keys.language)
            Self.applyLanguage(appLanguage, defaults: defaults)
            onChange?(.language(appLanguage))
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !isSynchronizingLoginItem, readLoginItem else { return }
            let requested = launchAtLogin
            loginItemTask?.cancel()
            loginItemTask = Task { @MainActor [weak self] in
                let achieved = await LoginItemController.setEnabled(requested)
                guard !Task.isCancelled else { return }
                self?.applyLoginItemState(achieved, requested: requested)
            }
        }
    }

    /// Explains a disagreement between the toggle and macOS; the Settings window shows it
    /// with a shortcut to System Settings → General → Login Items.
    private(set) var launchAtLoginNotice: String?

    /// Re-reads the system state. The user can flip the switch in System Settings at any
    /// time, so this runs whenever the app becomes active and when Settings appears.
    func refreshLoginItemState() {
        guard readLoginItem else { return }
        applyLoginItemState(LoginItemController.state, requested: nil)
    }

    private func applyLoginItemState(_ state: LoginItemController.State, requested: Bool?) {
        switch state {
        case .enabled:
            launchAtLoginNotice = nil
        case .requiresApproval:
            // Registered, but switched off in System Settings. macOS does not let an app
            // re-enable what the user turned off, so this is the only way forward.
            launchAtLoginNotice = String(localized: "Only System Settings can turn this back on. Open Login Items and allow PlanMonitor.")
        case .disabled:
            if requested == true {
                // Report what ServiceManagement actually said, when it said anything.
                launchAtLoginNotice = LoginItemController.lastErrorDescription
                    ?? String(localized: "macOS did not enable the login item. Open Login Items to turn it on.")
            } else {
                launchAtLoginNotice = nil
            }
        }
        synchronizeLoginItem()
    }

    private enum Keys {
        static let pollingInterval = "pollingIntervalMinutes"
        static let showRemaining = "showRemainingPercent"
        static let language = "appLanguage"
    }

    private let defaults: UserDefaults
    private let readLoginItem: Bool
    private var isSynchronizingLoginItem = false
    private var loginItemTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, readLoginItem: Bool = true) {
        self.defaults = defaults
        self.readLoginItem = readLoginItem
        HostMigration.run(defaults: defaults)

        let storedInterval = defaults.object(forKey: Keys.pollingInterval) as? Int ?? 5
        pollingIntervalMinutes = Self.repairedPollingInterval(storedInterval)
        showRemainingPercent = defaults.object(forKey: Keys.showRemaining) as? Bool ?? true
        appLanguage = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
        launchAtLogin = readLoginItem ? LoginItemController.isEnabled : false

        defaults.set(pollingIntervalMinutes, forKey: Keys.pollingInterval)
        defaults.set(showRemainingPercent, forKey: Keys.showRemaining)
        defaults.set(appLanguage.rawValue, forKey: Keys.language)
        Self.applyLanguage(appLanguage, defaults: defaults)
        if readLoginItem {
            LoginItemController.syncActivityWithCurrentSetting()
            applyLoginItemState(LoginItemController.state, requested: nil)
        }
    }

    func publishCurrentValues() {
        onChange?(.pollingInterval(pollingIntervalMinutes))
        onChange?(.percentageMode(showRemainingPercent))
        onChange?(.language(appLanguage))
    }

    private func synchronizeLoginItem() {
        isSynchronizingLoginItem = true
        launchAtLogin = LoginItemController.isEnabled
        isSynchronizingLoginItem = false
    }

    nonisolated static func repairedPollingInterval(_ value: Int) -> Int {
        supportedPollingIntervals.min { lhs, rhs in
            let lhsDistance = abs(lhs - value)
            let rhsDistance = abs(rhs - value)
            return lhsDistance == rhsDistance ? lhs < rhs : lhsDistance < rhsDistance
        } ?? 5
    }

    private static func applyLanguage(_ language: AppLanguage, defaults: UserDefaults) {
        if let localeIdentifier = language.localeIdentifier {
            defaults.set([localeIdentifier], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}

/// One-time copies of pre-combo preference keys into their namespaced homes. Every step is a
/// copy-if-absent, so the legacy key stays for rollback and running twice changes nothing.
/// Steps are versioned: a new build adds a step and bumps `currentVersion`; earlier steps are
/// skipped on installs that already passed them.
enum HostMigration {
    static let markerKey = "host.comboMigration.version"
    static let currentVersion = 2

    private static let steps: [(version: Int, run: (UserDefaults) -> Void)] = [
        (1, { defaults in
            migrate("trackSessionTime", to: "claude.trackSessionTime", defaults: defaults)
            migrate("sessionCheckIntervalMinutes", to: "claude.sessionCheckIntervalMinutes", defaults: defaults)
            migrate("sessionResetHour", to: "claude.sessionResetHour", defaults: defaults)
            migrate("showDisabledKeys", to: "openrouter.showDisabledKeys", defaults: defaults)
            migrate("menuBarDisplay", to: "openrouter.menuBarDisplay", defaults: defaults)
            migrate("spendBreakdownExpanded", to: "openrouter.spendBreakdownExpanded", defaults: defaults)
            migrate("showRecentModels", to: "openrouter.showRecentModels", defaults: defaults)
            migrate("recentModelsWindow", to: "openrouter.recentModelsWindow", defaults: defaults)
        }),
        (2, { defaults in
            // Session-tracker state moved into the Claude namespace when the tracker became
            // provider-neutral. The last-known utilization is re-seeded on the next tick.
            migrate("sessionAccumulatedSeconds", to: "claude.session.accumulatedSeconds", defaults: defaults)
            migrate("sessionLastResetDate", to: "claude.session.lastResetDate", defaults: defaults)
            for key in ["didLaunchCleanly", "lastLaunchDate", "lastLaunchTimestamp",
                        "lastHeartbeatDate", "lastHeartbeatTimestamp", "lastBreadcrumbs"] {
                migrate("appRuntime.\(key)", to: "host.runtime.\(key)", defaults: defaults)
            }
        })
    ]

    static func run(defaults: UserDefaults = .standard) {
        let completed = defaults.integer(forKey: markerKey)
        // The v1 marker was a bare `true`; treat it as version 1.
        let baseline = completed == 0 && defaults.object(forKey: "host.comboMigration.v1") != nil ? 1 : completed
        for step in steps where step.version > baseline {
            step.run(defaults)
        }
        if baseline < currentVersion {
            defaults.set(currentVersion, forKey: markerKey)
        }
    }

    private static func migrate(_ legacyKey: String, to newKey: String, defaults: UserDefaults) {
        guard defaults.object(forKey: newKey) == nil,
              let legacyValue = defaults.object(forKey: legacyKey) else { return }
        defaults.set(legacyValue, forKey: newKey)
    }
}
