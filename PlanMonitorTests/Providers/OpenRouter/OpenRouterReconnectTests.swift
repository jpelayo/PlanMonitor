import Foundation
import Testing
@testable import PlanMonitor

/// A rejection the key outlives is over: a successful poll puts the connection back, with the
/// identity the key last validated as. No other state is touched by a success.
@Suite("OpenRouter reconnect after a rejection")
@MainActor
struct OpenRouterReconnectTests {
    private let identity = KeyIdentity(label: "sk-or-v1-abc...123", isManagementKey: true, isFreeTier: false, expiresAt: nil)

    @Test func aGoodPollAfterARejectionReconnects() {
        let state = OpenRouterBudgetViewModel.connectionState(
            afterSuccessFrom: .invalidKey("This key was revoked, has expired or is not valid."),
            lastIdentity: identity
        )
        #expect(state == .connected(identity))
    }

    @Test func withoutAKnownIdentityThePlaceholderIsUsed() {
        let state = OpenRouterBudgetViewModel.connectionState(afterSuccessFrom: .invalidKey(""), lastIdentity: nil)
        #expect(state.isConnected)
        #expect(state.identity?.isManagementKey == true)
    }

    @Test(arguments: [ConnectionState.disconnected, .validating])
    func otherStatesAreLeftAlone(_ state: ConnectionState) {
        #expect(OpenRouterBudgetViewModel.connectionState(afterSuccessFrom: state, lastIdentity: identity) == state)
    }

    @Test func aConnectedStateKeepsItsOwnIdentity() {
        let other = KeyIdentity(label: "other", isManagementKey: true, isFreeTier: false, expiresAt: nil)
        let state = OpenRouterBudgetViewModel.connectionState(afterSuccessFrom: .connected(other), lastIdentity: identity)
        #expect(state == .connected(other))
    }
}
