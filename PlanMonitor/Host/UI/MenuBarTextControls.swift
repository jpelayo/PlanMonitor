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
