import Foundation
import Testing
@testable import PlanMonitor

/// What a failed poll proves about the session. Only lost credentials sign Grok out; a refused
/// fresh token is unproven and keeps what is shown; nothing here ever opens a window.
@Suite("Grok error outcome")
struct GrokErrorOutcomeTests {
    @Test func lostCredentialsSignOut() {
        #expect(GrokUsageViewModel.authOutcome(for: GrokAPIError.noAccessToken) == .signedOut)
    }

    @Test func aRefusedFreshTokenIsInconclusive() {
        #expect(GrokUsageViewModel.authOutcome(for: GrokAPIError.unauthorized) == .inconclusive)
    }

    @Test(arguments: [
        GrokAPIError.forbidden,
        .rateLimited(nil),
        .network(URLError(.notConnectedToInternet)),
        .invalidResponse(endpoint: "billing", statusCode: 500),
        .noWeeklyUsage,
        .unsupportedPrincipal,
    ])
    func otherAPIErrorsAreOrdinary(_ error: GrokAPIError) {
        #expect(GrokUsageViewModel.authOutcome(for: error) == .ordinary)
    }

    @Test func aNonAPIErrorIsOrdinary() {
        #expect(GrokUsageViewModel.authOutcome(for: URLError(.timedOut)) == .ordinary)
    }
}
