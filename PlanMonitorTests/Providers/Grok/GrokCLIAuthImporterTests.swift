import Foundation
import Testing
@testable import PlanTracker

struct GrokCLIAuthImporterTests {
    @Test func importsValidOIDCRecordAmongOthers() throws {
        let json = """
        {
          "https://other.example::abc": { "auth_mode": "password" },
          "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828": {
            "auth_mode": "oidc",
            "email": "user@example.com",
            "key": "access-token",
            "refresh_token": "refresh-token",
            "expires_at": "2026-08-29T15:42:56Z",
            "oidc_issuer": "https://auth.x.ai",
            "oidc_client_id": "b1a00492-073a-47ea-816f-4c329264a828",
            "principal_type": "User",
            "first_name": "Ada",
            "last_name": "Lovelace"
          }
        }
        """
        let credentials = try GrokCLIAuthImporter.importCredentials(from: Data(json.utf8))
        #expect(credentials.accessToken == "access-token")
        #expect(credentials.refreshToken == "refresh-token")
        #expect(credentials.email == "user@example.com")
        #expect(credentials.displayName == "Ada Lovelace")
        #expect(credentials.identity.isPersonalAccount)
    }

    @Test func rejectsWrongIssuer() {
        let json = """
        {"auth_mode":"oidc","oidc_issuer":"https://evil.example","oidc_client_id":"b1a00492-073a-47ea-816f-4c329264a828","key":"a","refresh_token":"b"}
        """
        #expect(throws: GrokCLIAuthImporterError.unsupportedIssuer) {
            try GrokCLIAuthImporter.importCredentials(from: Data(json.utf8))
        }
    }

    @Test func rejectsMissingTokens() {
        let json = """
        {"auth_mode":"oidc","oidc_issuer":"https://auth.x.ai","oidc_client_id":"b1a00492-073a-47ea-816f-4c329264a828","key":"","refresh_token":""}
        """
        #expect(throws: GrokCLIAuthImporterError.missingTokens) {
            try GrokCLIAuthImporter.importCredentials(from: Data(json.utf8))
        }
    }

    @Test func rejectsNonOIDC() {
        let json = """
        {"auth_mode":"password","oidc_issuer":"https://auth.x.ai","oidc_client_id":"b1a00492-073a-47ea-816f-4c329264a828","key":"a","refresh_token":"b"}
        """
        #expect(throws: GrokCLIAuthImporterError.unsupportedAuthMode) {
            try GrokCLIAuthImporter.importCredentials(from: Data(json.utf8))
        }
    }
}
