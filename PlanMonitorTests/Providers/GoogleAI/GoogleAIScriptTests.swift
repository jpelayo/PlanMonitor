import Foundation
import Testing
@testable import PlanMonitor

/// The helper script's text and the version check. The script is never run by the suite.
@Suite("Google AI helper script")
struct GoogleAIScriptTests {

    @Test func theScriptDeclaresItsVersion() {
        #expect(GoogleAIScript.installedVersion(of: GoogleAIScript.contents) == GoogleAIScript.version)
        #expect(GoogleAIScript.state(forInstalledText: GoogleAIScript.contents) == .installed)
    }

    @Test func theScriptOnlyAsksForTheUsageReportWithItsGuards() {
        let text = GoogleAIScript.contents
        #expect(text.hasPrefix("#!/bin/sh\n"))
        #expect(text.contains("-p /usage --output-format json"))
        // CodexBar found agy ignores `1`: only the literal `true` turns auto-update off.
        #expect(text.contains("AGY_CLI_DISABLE_AUTO_UPDATE=true"))
        #expect(text.contains(#"BROWSER="$WORK/open""#))
        #expect(text.contains(GoogleAIScript.agyNotFoundMarker))
        #expect(text.contains("exit 127"))
    }

    @Test func anOlderOrUnmarkedCopyIsOutdated() {
        #expect(GoogleAIScript.state(forInstalledText: "#!/bin/sh\n# planmonitor-agy-usage v0\n") == .outdated(found: 0))
        #expect(GoogleAIScript.state(forInstalledText: "#!/bin/sh\necho hi\n") == .outdated(found: 0))
        #expect(GoogleAIScript.state(forInstalledText: nil) == .notInstalled)
    }

    @Test func aNewerCopyCountsAsInstalled() {
        #expect(GoogleAIScript.state(forInstalledText: "#!/bin/sh\n# planmonitor-agy-usage v99\n") == .installed)
    }
}
