import Foundation

/// Whether the helper script is in the app's Application Scripts folder, and which version.
nonisolated enum GoogleAIScriptState: Equatable, Sendable {
    case notInstalled
    /// Installed, but an older version than this build writes.
    case outdated(found: Int)
    case installed
}

/// Why a run produced no figures. Only the kind is kept: agy's stderr is never shown or logged.
nonisolated enum GoogleAIRunError: Error, Equatable, Sendable {
    /// The script is not installed: nothing was run.
    case scriptMissing
    /// The script found no `agy` executable (exit 127 with its marker).
    case agyNotFound
    /// agy ran and failed — typically not signed in, or a version without print mode.
    case agyFailed(exit: Int32)
    /// agy answered with something that is not a usage report this build can read.
    case reportChanged
    /// No answer within the time limit.
    case timedOut
    /// macOS refused to run the script.
    case launchFailed

    /// Worth retrying on the next cycle with the figures kept. The setup states are not: they
    /// need the user.
    var isTransient: Bool {
        switch self {
        case .scriptMissing, .agyNotFound: false
        case .agyFailed, .reportChanged, .timedOut, .launchFailed: true
        }
    }

    /// Needs the setup window rather than a retry.
    var needsSetup: Bool { !isTransient }

    var message: String {
        switch self {
        case .scriptMissing:
            String(localized: "The helper script is not installed.")
        case .agyNotFound:
            String(localized: "The agy command was not found. Install the Antigravity CLI.")
        case .agyFailed:
            String(localized: "agy could not read your usage. Run agy in Terminal and sign in.")
        case .reportChanged:
            String(localized: "agy's usage report has changed. Update PlanMonitor.")
        case .timedOut:
            String(localized: "agy did not answer in time.")
        case .launchFailed:
            String(localized: "macOS could not run the helper script.")
        }
    }
}
