import AppKit
import Foundation
import Testing
@testable import PlanMonitor

/// A refused key shows no figures anywhere — not in the dropdown, not on the bar — even though
/// the snapshot is kept for when the key is accepted again.
@Suite("OpenRouter refused key")
@MainActor
struct OpenRouterKeyRejectionTests {
    private func label(_ state: ConnectionState, display: MenuBarDisplay) -> MenuBarLabel {
        OpenRouterMenuBarLabel.make(
            snapshot: DemoSnapshot.make(),
            connectionState: state,
            display: display,
            currencyStyle: .default,
            ringFill: nil,
            font: MenuBarLabel.defaultFont
        )
    }

    @Test(arguments: [MenuBarDisplay.amount, .percent])
    func aRefusedKeyShowsNoFigures(_ display: MenuBarDisplay) {
        let refused = label(.invalidKey("This key was revoked, has expired or is not valid."), display: display)
        #expect(refused.text == nil)
        #expect(refused.textTint == nil)
        #expect(refused.symbolTint == BudgetSeverity.normal.iconTint)
    }

    @Test func aConnectedKeyStillShowsItsCredit() {
        let identity = KeyIdentity(label: "demo", isManagementKey: true, isFreeTier: false, expiresAt: nil)
        #expect(label(.connected(identity), display: .amount).text != nil)
    }
}
