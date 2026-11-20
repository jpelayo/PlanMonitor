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
    /// What the figure is: "Credit", "Credit left", "To be invoiced". Empty on an action line.
    var kind: String = ""
    /// When the figure resets or expires, already formatted by the provider as its dropdown writes it.
    var date: String? = nil
    /// Already formatted by the provider. `nil` on an action line.
    var amount: String? = nil
    var critical = false
    /// Signed out or key refused: the provider's name and this button where the amount goes.
    var action: BalanceAction? = nil
}

/// The one button a money provider's Balances line shows when it has no figure to show.
struct BalanceAction: Equatable {
    let title: String
    let window: WindowRouter.AppWindow
}

/// What the grouped dropdown needs from one provider. Built in the composition root next to the
/// provider's own status-item definition, from the same view model.
struct GroupedMenuEntry {
    let id: ProviderID
    /// The provider's compact section: its own view, reading only its own view model. `nil` for
    /// the money providers (OpenRouter, Claude-API), which show only their Balances lines.
    let section: (() -> AnyView)?
    let refresh: @MainActor @Sendable () async -> Void
    let isRefreshing: () -> Bool
    let nextRefreshAt: () -> Date?
    /// Signed in or connected, and not in demo — the same conditions that enable its own Refresh.
    let canRefresh: () -> Bool
    let isDemo: () -> Bool
    let balances: () -> [BalanceLine]
}
