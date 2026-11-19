import Foundation
import Testing
@testable import PlanMonitor

/// After a 401/403, Codex re-reads with its stored session and then the WebView cookies. Only
/// when both definitively say no is the session over — shown signed out, no gauges. Anything
/// unproven keeps the gauges with a neutral line, never "Session expired".
@Suite("Codex recovery outcome")
@MainActor
struct CodexRecoveryOutcomeTests {
    typealias Outcome = CodexUsageViewModel.RecoveryOutcome

    @Test func eitherRecoveryWins() {
        #expect(Outcome.combine(.recovered, .rejected) == .recovered)
        #expect(Outcome.combine(.rejected, .recovered) == .recovered)
        #expect(Outcome.combine(.inconclusive, .recovered) == .recovered)
    }

    @Test func anyDoubtKeepsTheGauges() {
        #expect(Outcome.combine(.inconclusive, .rejected) == .inconclusive)
        #expect(Outcome.combine(.rejected, .inconclusive) == .inconclusive)
        #expect(Outcome.combine(.inconclusive, .inconclusive) == .inconclusive)
    }

    @Test func onlyTwoRejectionsSignOut() {
        #expect(Outcome.combine(.rejected, .rejected) == .rejected)
    }

    @Test func theIdentityEndpointsNoIsDefinitive() {
        #expect(Outcome.failure(OpenAIAPIClient.APIError.unauthorized) == .rejected)
        #expect(Outcome.failure(OpenAIAPIClient.APIError.forbidden) == .rejected)
        #expect(Outcome.failure(OpenAIAPIClient.APIError.noSessionCookies) == .rejected)
    }

    @Test func everythingElseIsUnproven() {
        #expect(Outcome.failure(OpenAIAPIClient.APIError.networkError(URLError(.notConnectedToInternet))) == .inconclusive)
        #expect(Outcome.failure(OpenAIAPIClient.APIError.invalidResponse(endpoint: "me", statusCode: 500, bodyPreview: nil)) == .inconclusive)
        #expect(Outcome.failure(SecureStoreError.locked) == .inconclusive)
        #expect(Outcome.failure(URLError(.timedOut)) == .inconclusive)
    }
}
