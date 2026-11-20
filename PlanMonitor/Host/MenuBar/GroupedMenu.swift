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

/// The user's four text sizes for the grouped dropdown (Settings › Grouped menu): one control for
/// the provider names (section titles and the dollar rows' names), one for the dollar amounts.
nonisolated enum GroupedTextSize: String, CaseIterable, Sendable {
    case small
    case regular
    case big
    case huge

    /// The user's own steps (2026-11-20). Regular is today's subheadline title.
    var points: CGFloat {
        switch self {
        case .small: 9
        case .regular: 11
        case .big: 15
        case .huge: 18
        }
    }

    var displayName: String {
        switch self {
        case .small: String(localized: "Small")
        case .regular: String(localized: "Regular")
        case .big: String(localized: "Big")
        case .huge: String(localized: "Huge")
        }
    }
}

/// The user's order for the grouped dropdown: all six providers, sections and Balances rows alike.
nonisolated enum GroupedMenuOrder {
    /// Stored raw ids → every provider once, in the user's order. Known ids keep their stored
    /// place; a provider missing from storage (a new one) is appended in `ProviderID` order, so it
    /// lands last; unknown or repeated ids are skipped. Nothing stored → `ProviderID.allCases`.
    static func repaired(_ stored: [String]?) -> [ProviderID] {
        var order: [ProviderID] = []
        for raw in stored ?? [] {
            if let id = ProviderID(rawValue: raw), !order.contains(id) {
                order.append(id)
            }
        }
        for id in ProviderID.allCases where !order.contains(id) {
            order.append(id)
        }
        return order
    }

    /// `ids` in the order `order` gives them; an id `order` lacks keeps its `ProviderID` place
    /// after the rest.
    static func sorted(_ ids: [ProviderID], by order: [ProviderID]) -> [ProviderID] {
        let rank = { (id: ProviderID) -> Int in
            order.firstIndex(of: id) ?? (order.count + (ProviderID.allCases.firstIndex(of: id) ?? 0))
        }
        return ids.sorted { rank($0) < rank($1) }
    }
}

extension EnvironmentValues {
    /// Size of the provider names in the grouped dropdown. Set by `GroupedMenuBarView`.
    @Entry var groupedTitleSize: GroupedTextSize = .regular
    /// Size of the dollar amounts in the grouped dropdown's Balances rows.
    @Entry var groupedAmountSize: GroupedTextSize = .regular
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
