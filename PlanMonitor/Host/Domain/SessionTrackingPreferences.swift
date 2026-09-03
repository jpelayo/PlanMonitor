import Foundation

/// Per-provider session-time settings. Keys are `<namespace>.trackSessionTime`,
/// `<namespace>.sessionCheckIntervalMinutes`, `<namespace>.sessionResetHour` — the names the
/// Claude and Codex view models already used, so existing values carry over unchanged.
@MainActor
@Observable
final class SessionTrackingPreferences {
    static let defaultCheckIntervalMinutes = 5
    static let defaultResetHour = 4
    static let resetHours = [0, 1, 2, 3, 4, 5, 6]

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: keys.enabled) }
    }

    var checkIntervalMinutes: Int {
        didSet { defaults.set(checkIntervalMinutes, forKey: keys.interval) }
    }

    var resetHour: Int {
        didSet { defaults.set(resetHour, forKey: keys.resetHour) }
    }

    var checkInterval: TimeInterval {
        TimeInterval(checkIntervalMinutes * 60)
    }

    private let defaults: UserDefaults
    private let keys: Keys

    private struct Keys {
        let enabled: String
        let interval: String
        let resetHour: String

        init(namespace: String) {
            enabled = "\(namespace).trackSessionTime"
            interval = "\(namespace).sessionCheckIntervalMinutes"
            resetHour = "\(namespace).sessionResetHour"
        }
    }

    init(namespace: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keys = Keys(namespace: namespace)

        isEnabled = defaults.object(forKey: keys.enabled) as? Bool ?? false

        let storedInterval = defaults.integer(forKey: keys.interval)
        checkIntervalMinutes = SessionCheckInterval(rawValue: storedInterval)?.rawValue
            ?? Self.defaultCheckIntervalMinutes

        if defaults.object(forKey: keys.resetHour) != nil,
           Self.resetHours.contains(defaults.integer(forKey: keys.resetHour)) {
            resetHour = defaults.integer(forKey: keys.resetHour)
        } else {
            resetHour = Self.defaultResetHour
        }
    }
}
