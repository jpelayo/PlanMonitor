import Foundation
import Testing
@testable import PlanMonitor

/// The Debug console log is pasted into conversations, so what it may never contain is tested,
/// not promised: cookie values, query strings, fragments, path-borne tokens, email addresses.
@Suite("Claude-API diagnostics")
struct ClaudePlatformDiagnosticsTests {

    @Test func urlsKeepHostAndPathOnly() throws {
        let url = try #require(URL(string: "https://platform.claude.com/login/callback?code=SECRET123&state=x#token=SECRET456"))
        let line = ClaudePlatformDiagnostics.redacted(url)
        #expect(line == "platform.claude.com/login/callback")
        #expect(!line.contains("SECRET"))
    }

    @Test func tokenLikePathSegmentsAreShortened() throws {
        let url = try #require(URL(string: "https://platform.claude.com/magic-link/AbCdEfGhIjKlMnOpQrStUvWxYz012345"))
        let line = ClaudePlatformDiagnostics.redacted(url)
        #expect(line == "platform.claude.com/magic-link/AbCd…")
    }

    @Test func cookiesAreNamedNeverValued() throws {
        let cookie = try #require(HTTPCookie(properties: [
            .domain: ".claude.com", .path: "/", .name: "sessionKey", .value: "sk-ant-sid01-SECRET"
        ]))
        let line = ClaudePlatformDiagnostics.names([cookie, cookie])
        #expect(line == "[sessionKey]")
        #expect(ClaudePlatformDiagnostics.names(inHeader: "sessionKey=SECRET; __cf_bm=EDGE") == "[__cf_bm, sessionKey]")
    }

    @Test func emailsAreScrubbedFromOrgNames() {
        #expect(ClaudePlatformDiagnostics.scrubEmails("someone@example.com's Organization") == "<email>'s Organization")
        #expect(ClaudePlatformDiagnostics.scrubEmails("Acme Research") == "Acme Research")
    }

    @Test func bootstrapIsDescribedWithoutTheEmail() throws {
        let json = try JSONSerialization.jsonObject(with: Data(#"""
        {"account":{"email_address":"someone@example.com","uuid":"u","memberships":[
          {"organization":{"uuid":"37fd2a8d-46c7-4f8b-883c-54f91b4b524a","name":"someone@example.com's Organization","capabilities":["api"]}}
        ]}}
        """#.utf8))
        let line = ClaudePlatformDiagnostics.describeBootstrap(json)

        #expect(!line.contains("someone@example.com"))
        #expect(line.contains("email present: true"))
        #expect(line.contains("37fd2a8d…"))
        #expect(line.contains("[\"api\"]"))
    }

    @Test func signedOutBootstrapSaysSo() throws {
        let json = try JSONSerialization.jsonObject(with: Data(#"{"account":null}"#.utf8))
        #expect(ClaudePlatformDiagnostics.describeBootstrap(json) == "bootstrap: account is null (signed out)")
    }

    @Test func aPollIsDescribedInMoney() throws {
        let line = ClaudePlatformDiagnostics.describe(try ClaudePlatformFixtures.capturedSnapshot())
        #expect(line.contains("promo 199.54 USD left of 200.00 USD"))
        #expect(line.contains("spend 0.46 USD of enforced 500.00 USD"))
        #expect(line.contains("to be invoiced nil"))
        #expect(line.contains("auto-payment off"))
    }
}
