import AppKit
import SwiftUI

/// When the single grouped menu-bar item replaces the per-provider items.
nonisolated enum GroupedMenuRule {
    /// The user's choice, and at least two **enabled** providers. Counting enabled providers —
    /// the checkboxes — rather than signed-in ones means a sign-out, an expired session or a
    /// locked Keychain never swaps the items under the user. With one provider, grouping would
    /// only hide that provider's own figures behind a plain ring, so the choice waits, unchanged.
    static func isEffective(preference: Bool, enabledCount: Int) -> Bool {
        preference && enabledCount >= 2
    }

    /// The switches are offered only where they can take effect.
    static func offersSwitch(enabledCount: Int) -> Bool {
        enabledCount >= 2
    }
}

/// The grouped item's label: Codex's plain dashed ring, never tinted, no text. It stands for the
/// whole app, so it carries no single provider's severity.
enum GroupedMenuBarLabel {
    static func make() -> MenuBarLabel {
        MenuBarLabel(
            symbolName: "ring.dashed",
            fallbackSymbol: "ring.dashed",
            accessibilityLabel: "PlanMonitor"
        )
    }
}

/// One line of the grouped dropdown's Balances block. Each money provider builds its own, with
/// its own figures and its own currency style; the host only lays them out.
struct BalanceLine: Identifiable, Equatable {
    let id: String
    /// The provider's display name.
    let provider: String
    /// What the figure is: "Credit", "Credit left", "To be invoiced".
    let kind: String
    /// Already formatted by the provider.
    let amount: String
    var critical = false
}

/// What the grouped dropdown needs from one provider. Built in the composition root next to the
/// provider's own status-item definition, from the same view model.
struct GroupedMenuEntry {
    let id: ProviderID
    /// The provider's compact section: its own view, reading only its own view model.
    let section: () -> AnyView
    let refresh: @MainActor @Sendable () async -> Void
    let isRefreshing: () -> Bool
    let nextRefreshAt: () -> Date?
    /// Signed in or connected, and not in demo — the same conditions that enable its own Refresh.
    let canRefresh: () -> Bool
    let isDemo: () -> Bool
    let balances: () -> [BalanceLine]
}
