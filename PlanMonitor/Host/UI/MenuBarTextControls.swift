import SwiftUI

/// What a provider's menu-bar digits show. A separate view rather than a flag on
/// `MenuBarTextControls`, because OpenRouter uses that control but has its own money-shaped
/// "Menu bar shows" picker — an opt-out default would silently give a future provider this one too.
struct MenuBarUsageDisplayControl: View {
    @Bindable var preferences: MenuBarTextPreferences

    var body: some View {
        Picker(String(localized: "Menu bar shows"), selection: $preferences.usageDisplay) {
            ForEach(MenuBarUsageDisplay.allCases, id: \.self) { display in
                Text(display.displayName).tag(display)
            }
        }
        .pickerStyle(.menu)
    }
}

/// The ring around a provider's menu-bar glyph: which window fills it, and whether it fills with
/// what is left or what is spent. A separate view for the same reason as the control above —
/// OpenRouter's ring is money-driven and computed by its own label maker, so it must not inherit
/// this one by default.
struct MenuBarRingControl: View {
    @Bindable var preferences: MenuBarTextPreferences

    var body: some View {
        Picker(String(localized: "Menu bar ring"), selection: $preferences.ringSource) {
            ForEach(MenuBarRingSource.allCases, id: \.self) { source in
                Text(source.displayName).tag(source)
            }
        }
        .pickerStyle(.menu)

        Picker(String(localized: "Ring shows"), selection: $preferences.ringSense) {
            ForEach(MenuBarRingSense.allCases, id: \.self) { sense in
                Text(sense.displayName).tag(sense)
            }
        }
        .pickerStyle(.menu)
        // Disabled rather than hidden: the section keeps its height and the option stays visible.
        .disabled(preferences.ringSource == .off)
    }
}

/// Width and size of the digits a provider shows in the menu bar. Same two pickers in every
/// provider section.
struct MenuBarTextControls: View {
    @Bindable var preferences: MenuBarTextPreferences

    var body: some View {
        Picker(String(localized: "Menu bar digit width"), selection: $preferences.width) {
            ForEach(MenuBarDigitWidth.allCases, id: \.self) { width in
                Text(width.displayName).tag(width)
            }
        }
        .pickerStyle(.menu)

        Picker(String(localized: "Menu bar digit size"), selection: $preferences.size) {
            ForEach(MenuBarDigitSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
        .pickerStyle(.menu)
    }
}
