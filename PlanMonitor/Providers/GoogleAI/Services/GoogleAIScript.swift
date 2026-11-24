import Foundation

/// The helper script PlanMonitor asks the user to install in its Application Scripts folder.
///
/// The sandbox forbids the app from starting `agy` itself. macOS lets a sandboxed app run a script
/// the **user** placed in `~/Library/Application Scripts/<bundle id>/` (`NSUserUnixTask`); that
/// script runs outside the sandbox, as the user, and the app reads what it prints. All it does is
/// `agy -p /usage --output-format json` — no prompt is sent — with the guards a passive probe
/// needs (as CodexBar runs it): agy's auto-update off (the literal `true` is required), `open` and
/// `xdg-open` replaced by launchers that fail so a lapsed sign-in can never pop a browser, and a
/// private working folder so no project's settings are read.
nonisolated enum GoogleAIScript {
    static let fileName = "planmonitor-agy-usage.sh"
    /// Raised whenever the text below changes, so an installed older copy reads as outdated.
    static let version = 1
    static let versionMarker = "# planmonitor-agy-usage v"
    /// Printed on stderr, with exit 127, when no `agy` is found.
    static let agyNotFoundMarker = "PLANMONITOR_AGY_NOT_FOUND"

    static let contents = """
    #!/bin/sh
    \(versionMarker)\(version)
    # Installed by PlanMonitor for its Google AI provider. Prints your Antigravity limits by running
    # `agy -p /usage --output-format json`: no prompt is sent, no browser is opened, agy is never updated.
    set -u
    AGY="${PLANMONITOR_AGY:-}"
    if [ -z "$AGY" ]; then
      for c in "$HOME/.local/bin/agy" /opt/homebrew/bin/agy /usr/local/bin/agy; do
        if [ -x "$c" ]; then AGY="$c"; break; fi
      done
    fi
    if [ -z "$AGY" ]; then AGY="$(/bin/zsh -lc 'command -v agy' 2>/dev/null)"; fi
    if [ -z "$AGY" ] || [ ! -x "$AGY" ]; then echo \(agyNotFoundMarker) >&2; exit 127; fi
    WORK="$(/usr/bin/mktemp -d)" || exit 1
    trap '/bin/rm -rf "$WORK"' EXIT
    printf '#!/bin/sh\\nexit 1\\n' > "$WORK/open"
    /bin/cp "$WORK/open" "$WORK/xdg-open"
    /bin/chmod 755 "$WORK/open" "$WORK/xdg-open"
    cd "$WORK" || exit 1
    PATH="$WORK:/usr/bin:/bin:/usr/sbin:/sbin" BROWSER="$WORK/open" AGY_CLI_DISABLE_AUTO_UPDATE=true \\
      "$AGY" -p /usage --output-format json

    """

    /// The version an installed copy declares, from its marker line; `nil` when it carries none.
    static func installedVersion(of text: String) -> Int? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(5) {
            guard line.hasPrefix(versionMarker) else { continue }
            return Int(line.dropFirst(versionMarker.count).prefix { $0.isNumber })
        }
        return nil
    }

    /// Installed and current, older, or absent — from the file's text (`nil` = no file).
    static func state(forInstalledText text: String?) -> GoogleAIScriptState {
        guard let text else { return .notInstalled }
        guard let found = installedVersion(of: text) else { return .outdated(found: 0) }
        return found >= version ? .installed : .outdated(found: found)
    }
}
