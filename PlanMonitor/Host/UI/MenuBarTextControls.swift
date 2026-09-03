import SwiftUI

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
