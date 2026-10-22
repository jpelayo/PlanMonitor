import Foundation
import Testing
@testable import PlanMonitor

/// App Review sees only demo mode, so the demo must fill every row the dropdown draws; and the
/// connect flow must store a key only after the API accepted it.
@Suite("OpenCode demo and connect")
@MainActor
struct OpenCodeDemoTests {

    @Test func theDemoPopulatesEveryRow() {
        let snapshot = OpenCodeDemoSnapshot.snapshot()

        #expect(snapshot.spent != nil)                      // gauge: used
        #expect(snapshot.budget != nil)                     // …available and remaining
        #expect(snapshot.usedFraction != nil)               // …the bar
        #expect(snapshot.resetsAt != nil)                   // …the reset lines
        #expect(snapshot.budgetSource == .custom)           // "Budget" info row
        #expect(snapshot.memberEmail != nil)                // header identity
        #expect(!snapshot.isWorkspaceTotal)
        #expect(!snapshot.exceeded)
        #expect(snapshot.hasSpend)
        let go = snapshot.go
        #expect(go?.rolling?.resetsAt != nil)               // the three Go cards
        #expect(go?.weekly?.resetsAt != nil)
        #expect(go?.monthly?.resetsAt != nil)
        #expect(go?.isRateLimited == false)
    }

    /// The weekly card's reset moment is the backend's own boundary: Monday 00:00 UTC.
    @Test func theDemoWeekResetsOnMondayUTC() throws {
        let thursday = OpenCodeFixtures.utc("2026-10-22T17:00:00Z")
        let reset = try #require(OpenCodeDemoSnapshot.snapshot(now: thursday).go?.weekly?.resetsAt)
        #expect(reset == OpenCodeFixtures.utc("2026-10-26T00:00:00Z"))
    }

    @Test func theDemoResetsAtTheNextUTCMonth() {
        let now = OpenCodeFixtures.utc("2026-10-22T17:00:00Z")
        #expect(OpenCodeDemoSnapshot.snapshot(now: now).resetsAt == OpenCodeFixtures.utc("2026-11-01T00:00:00Z"))
    }

    @Test func enteringDemoConnectsShowsDataAndPersistsNothing() async {
        await withDefaultsAsync { defaults in
            let viewModel = OpenCodeViewModel(secureStore: InMemorySecureStore(), defaults: defaults)

            viewModel.enterDemo()

            #expect(viewModel.isDemoMode)
            #expect(viewModel.connectionState == .connected(keyPrefix: OpenCodeDemoSnapshot.keyPrefix))
            #expect(viewModel.identityLabel == OpenCodeDemoSnapshot.identityLabel)
            #expect(viewModel.nextRefreshAt == nil)
            #expect(viewModel.degradedMessage == nil)
            #expect(defaults.data(forKey: OpenCodeSnapshotStore.key) == nil)

            let label = OpenCodeMenuBarLabel.make(
                snapshot: viewModel.snapshot,
                connectionState: viewModel.connectionState,
                display: viewModel.menuBarDisplay,
                showRemainingPercent: false,
                ringFill: viewModel.ringFill,
                font: MenuBarLabel.defaultFont
            )
            #expect(label.text == "38%")                    // the 5-hour window, the default
            #expect(label.symbolName == "pesetasign.ring.dashed")
        }
    }

    @Test func aDisconnectedLabelShowsNoFigures() {
        let label = OpenCodeMenuBarLabel.make(
            snapshot: OpenCodeDemoSnapshot.snapshot(),
            connectionState: .disconnected,
            display: .goRolling,
            showRemainingPercent: false,
            ringFill: nil,
            font: MenuBarLabel.defaultFont
        )
        #expect(label.text == nil)
        #expect(label.variableValue == nil)
    }

    @Test func choicesPersistUnderTheirOwnKeys() async {
        await withDefaultsAsync { defaults in
            let viewModel = OpenCodeViewModel(secureStore: InMemorySecureStore(), defaults: defaults)
            viewModel.menuBarDisplay = .goMonthly
            viewModel.ringSource = .budget
            viewModel.currencyStyle = .codeBefore
            viewModel.memberID = "user_alice"

            #expect(defaults.string(forKey: "opencode.menuBarDisplay") == "goMonthly")
            #expect(defaults.string(forKey: "opencode.ringSource") == "budget")
            #expect(defaults.string(forKey: "opencode.currencyStyle") == "codeBefore")
            #expect(defaults.string(forKey: "opencode.memberID") == "user_alice")

            let restored = OpenCodeViewModel(secureStore: InMemorySecureStore(), defaults: defaults)
            #expect(restored.menuBarDisplay == .goMonthly)
            #expect(restored.ringSource == .budget)
            #expect(restored.currencyStyle == .codeBefore)
            #expect(restored.memberID == "user_alice")
        }
    }

    // MARK: - Connect

    private static func stubbedClient(_ token: String, status: Int, json: String) -> OpenCodeAPIClient {
        StubURLProtocol.setStub(.init(status: status, body: Data(json.utf8), headers: [:]), for: token)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Case": token]
        return OpenCodeAPIClient(session: URLSession(configuration: config))
    }

    @Test func anAcceptedKeyIsStoredAndShowsItsBudget() async throws {
        try await withDefaultsAsync { defaults in
            let memory = InMemorySecureStore()
            let viewModel = OpenCodeViewModel(
                secureStore: memory,
                defaults: defaults,
                apiClient: Self.stubbedClient("opencode-connect-ok", status: 200, json: OpenCodeFixtures.docsExample)
            )

            let connected = await viewModel.connect(with: OpenCodeFixtures.testKey)
            await viewModel.suspend()

            #expect(connected)
            #expect(viewModel.connectError == nil)
            #expect(viewModel.connectionState == .connected(keyPrefix: "oc_sk_0123456789ab"))
            #expect(viewModel.snapshot.budget == OpenCodeFixtures.decimal("75.25"))
            #expect(await memory.accounts == [OpenCodeCredentialStore.account])
            let stored = try await OpenCodeCredentialStore(secureStore: memory).load()
            #expect(stored?.key == OpenCodeFixtures.testKey)
        }
    }

    @Test func aRefusedKeyIsNeverStored() async {
        await withDefaultsAsync { defaults in
            let memory = InMemorySecureStore()
            let viewModel = OpenCodeViewModel(
                secureStore: memory,
                defaults: defaults,
                apiClient: Self.stubbedClient("opencode-connect-401", status: 401, json: "{}")
            )

            let connected = await viewModel.connect(with: OpenCodeFixtures.testKey)

            #expect(!connected)
            #expect(viewModel.connectError == OpenCodeAPIError.unauthorized.errorDescription)
            #expect(viewModel.connectionState == .disconnected)
            #expect(await memory.accounts.isEmpty)
        }
    }

    @Test func aKeyOfAnotherShapeIsRefusedWithoutARequest() async {
        await withDefaultsAsync { defaults in
            let viewModel = OpenCodeViewModel(
                secureStore: InMemorySecureStore(),
                defaults: defaults,
                apiClient: Self.stubbedClient("opencode-connect-shape", status: 200, json: OpenCodeFixtures.docsExample)
            )

            let connected = await viewModel.connect(with: "sk-or-v1-0123456789abcdef0123")

            #expect(!connected)
            #expect(viewModel.connectError != nil)
            #expect(StubURLProtocol.requests(for: "opencode-connect-shape").isEmpty)
        }
    }
}
