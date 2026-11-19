import Foundation
import Testing
@testable import PlanMonitor

/// A refused key shows no figures anywhere — not in the dropdown, not on the bar — even though
/// the key and the snapshot are kept until the user replaces or removes the key.
@Suite("OpenCode refused key")
@MainActor
struct OpenCodeKeyRejectionTests {
    @Test func aRefusedKeyShowsNoFigures() {
        let label = OpenCodeMenuBarLabel.make(
            snapshot: OpenCodeDemoSnapshot.snapshot(),
            connectionState: .invalidKey(keyPrefix: "oc_sk_0123456789ab", reason: "This key was revoked, has expired or is not valid."),
            display: .goRolling,
            showRemainingPercent: false,
            ringFill: nil,
            font: MenuBarLabel.defaultFont
        )
        #expect(label.text == nil)
        #expect(label.textTint == nil)
        #expect(label.symbolTint == OpenCodeSeverity.normal.iconTint)
    }
}
