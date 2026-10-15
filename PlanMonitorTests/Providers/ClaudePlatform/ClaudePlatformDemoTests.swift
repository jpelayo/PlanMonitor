import Foundation
import Testing
@testable import PlanMonitor

/// App Review sees only demo mode. The Grok demo once stopped drawing a row because its data no
/// longer satisfied the view's condition; these hold Claude-API's demo to every row a pre-paid
/// account draws.
@Suite("Claude-API demo")
@MainActor
struct ClaudePlatformDemoTests {

    @Test func theDemoPopulatesEveryPrepaidRow() {
        let snapshot = ClaudePlatformDemoSnapshot.snapshot()

        #expect(snapshot.promoUsedFraction != nil)          // promotional credit gauge
        #expect(snapshot.promoExpiresAt != nil)             // …and its expiry
        #expect(snapshot.spendUsedFraction != nil)          // spend gauge
        #expect(snapshot.pauseLimit != nil)                 // …and its limits
        #expect(snapshot.prepaidRemaining != nil)           // prepaid row
        #expect(snapshot.autoRecharge != nil)               // auto-payment row
        #expect(snapshot.pendingInvoice == nil)             // pre-paid: nothing to invoice
        #expect(!snapshot.currencyMismatch)
    }

    @Test func theDemoMatchesTheCapturedAccount() throws {
        let demo = ClaudePlatformDemoSnapshot.snapshot()
        let captured = try ClaudePlatformFixtures.capturedSnapshot()

        #expect(demo.promoGranted == captured.promoGranted)
        #expect(demo.promoRemaining == captured.promoRemaining)
        #expect(demo.spendUsed == captured.spendUsed)
        #expect(demo.enforcedSpendLimit == captured.enforcedSpendLimit)
        #expect(demo.selfSelectedLimits == captured.selfSelectedLimits)
        #expect(demo.autoRecharge == captured.autoRecharge)
        #expect(demo.prepaidRemaining == captured.prepaidRemaining)
    }

    @Test func enteringDemoSignsInShowsDataAndPersistsNothing() async {
        await withDefaultsAsync { defaults in
            let viewModel = ClaudePlatformViewModel(secureStore: InMemorySecureStore(), defaults: defaults)

            viewModel.enterDemo()

            #expect(viewModel.isDemoMode)
            #expect(viewModel.authState == .authenticated(email: ClaudePlatformDemoSnapshot.identityLabel))
            #expect(viewModel.snapshot.promoGranted == 20_000)
            #expect(viewModel.nextRefreshAt == nil)
            #expect(viewModel.degradedMessage == nil)
            #expect(defaults.data(forKey: ClaudePlatformSnapshotStore.key) == nil)

            let label = ClaudePlatformMenuBarLabel.make(
                snapshot: viewModel.snapshot,
                authState: viewModel.authState,
                display: viewModel.menuBarDisplay,
                currencyStyle: viewModel.currencyStyle,
                ringFill: viewModel.ringFill,
                font: MenuBarLabel.defaultFont
            )
            #expect(label.text == "199$")
            #expect(label.symbolName == "eurosign.ring.dashed")
        }
    }

    @Test func signedOutLabelShowsNoFigures() {
        let label = ClaudePlatformMenuBarLabel.make(
            snapshot: ClaudePlatformDemoSnapshot.snapshot(),
            authState: .unauthenticated,
            display: .left,
            currencyStyle: .default,
            ringFill: nil,
            font: MenuBarLabel.defaultFont
        )
        #expect(label.text == nil)
        #expect(label.variableValue == nil)
    }

    @Test func displayAndRingChoicesPersistUnderTheirOwnKeys() async {
        await withDefaultsAsync { defaults in
            let viewModel = ClaudePlatformViewModel(secureStore: InMemorySecureStore(), defaults: defaults)
            viewModel.menuBarDisplay = .consumedOfUserLimit
            viewModel.ringSource = .promo
            viewModel.currencyStyle = .codeBefore
            #expect(defaults.string(forKey: "claudeapi.currencyStyle") == "codeBefore")
            #expect(ClaudePlatformViewModel(secureStore: InMemorySecureStore(), defaults: defaults).currencyStyle == .codeBefore)

            #expect(defaults.string(forKey: "claudeapi.menuBarDisplay") == "consumedOfUserLimit")
            #expect(defaults.string(forKey: "claudeapi.ringSource") == "promo")
            // Never the bare key `HostMigration` moved to OpenRouter.
            #expect(defaults.string(forKey: "menuBarDisplay") == nil)
            #expect(defaults.string(forKey: "openrouter.menuBarDisplay") == nil)

            let restored = ClaudePlatformViewModel(secureStore: InMemorySecureStore(), defaults: defaults)
            #expect(restored.menuBarDisplay == .consumedOfUserLimit)
            #expect(restored.ringSource == .promo)
        }
    }

    /// A choice from the retired eleven-entry list, still on disk, reads as the default.
    @Test func aRetiredChoiceFallsBackToTheDefault() async {
        await withDefaultsAsync { defaults in
            defaults.set("invoicedAmount", forKey: "claudeapi.menuBarDisplay")
            let viewModel = ClaudePlatformViewModel(secureStore: InMemorySecureStore(), defaults: defaults)
            #expect(viewModel.menuBarDisplay == .leftUnderUserLimit)
        }
    }
}
