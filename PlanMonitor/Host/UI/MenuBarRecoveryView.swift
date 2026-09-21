import AppKit
import SwiftUI

/// The app's lifeline when its menu bar items cannot be shown. On this OS a single ⌘-drag past
/// the edge — the user's or a menu-bar manager's — flips a per-app "Show in Menu Bar" switch in
/// System Settings that no app can flip back. Without this window the app would run, poll, and
/// be unreachable, because Settings opens only from the dropdown.
struct MenuBarRecoveryView: View {
    let openPlanMonitorSettings: () -> Void
    let resetPositions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "macOS has switched PlanMonitor off in System Settings › Menu Bar. A menu bar manager can do this without asking. PlanMonitor is running; turn it back on there and the items return."))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(String(localized: "Open Menu Bar settings")) {
                    Self.openMenuBarSettings()
                }
                .keyboardShortcut(.defaultAction)
                Button(String(localized: "Open PlanMonitor settings"), action: openPlanMonitorSettings)
                Spacer()
                Button(String(localized: "Reset menu bar positions"), action: resetPositions)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// The Menu Bar list inside Control Center's settings; the pane without the anchor is the
    /// fallback if the anchor is not honoured on this OS.
    private static func openMenuBarSettings() {
        let pane = "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
        let anchored = URL(string: pane + "?MenuBar")!
        if !NSWorkspace.shared.open(anchored) {
            NSWorkspace.shared.open(URL(string: pane)!)
        }
    }
}
