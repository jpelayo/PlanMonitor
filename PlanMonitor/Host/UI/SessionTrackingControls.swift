import SwiftUI

/// The three session-time settings, rendered identically in every provider section.
struct SessionTrackingControls: View {
    @Bindable var preferences: SessionTrackingPreferences

    var body: some View {
        Toggle(String(localized: "Track session time"), isOn: $preferences.isEnabled)
        if preferences.isEnabled {
            Picker(String(localized: "Session detection"), selection: $preferences.checkIntervalMinutes) {
                ForEach(SessionCheckInterval.allCases, id: \.rawValue) { interval in
                    Text(interval.displayName).tag(interval.rawValue)
                }
            }
            .pickerStyle(.menu)

            Picker(String(localized: "Daily reset"), selection: $preferences.resetHour) {
                ForEach(SessionTrackingPreferences.resetHours, id: \.self) { hour in
                    Text(Self.label(forHour: hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// "12:00 AM" / "4:00 AM" or "0:00" / "4:00", following the user's locale.
    static func label(forHour hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
