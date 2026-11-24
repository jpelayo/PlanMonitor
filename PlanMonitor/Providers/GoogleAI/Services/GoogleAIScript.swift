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
///
/// **v2 — one blink instead of a gear (user decision, 2026-11-24).** macOS's ScriptMonitor shows a
/// spinning gear in the menu bar for as long as the script runs; agy takes ~3 s. So each run prints
/// the report the *previous* run's background agy saved, starts the next one detached, and exits
/// in milliseconds: the gear only blinks, and the figures are one polling interval old. With no
/// result from the last 30 minutes (first run, after a long sleep) it runs agy in the foreground
/// once. A failed background run is reported by the next run with agy's exit status, as v1 did.
/// The cache holds only the usage report, in `~/Library/Caches/PlanMonitor-agy/` (mode 700).
nonisolated enum GoogleAIScript {
    static let fileName = "planmonitor-agy-usage.sh"
    /// Raised whenever the text below changes, so an installed older copy reads as outdated.
    static let version = 2
    static let versionMarker = "# planmonitor-agy-usage v"
    /// Printed on stderr, with exit 127, when no `agy` is found.
    static let agyNotFoundMarker = "PLANMONITOR_AGY_NOT_FOUND"

    static let contents = """
    #!/bin/sh
    \(versionMarker)\(version)
    # Installed by PlanMonitor for its Google AI provider. Prints your Antigravity limits by running
    # `agy -p /usage --output-format json`: no prompt is sent, no browser is opened, agy is never updated.
    # Each run prints the previous run's saved report and refreshes it in the background, so it ends
    # at once (macOS shows a gear while a script runs).
    set -u
    AGY="${PLANMONITOR_AGY:-}"
    if [ -z "$AGY" ]; then
      for c in "$HOME/.local/bin/agy" /opt/homebrew/bin/agy /usr/local/bin/agy; do
        if [ -x "$c" ]; then AGY="$c"; break; fi
      done
    fi
    if [ -z "$AGY" ]; then AGY="$(/bin/zsh -lc 'command -v agy' 2>/dev/null)"; fi
    if [ -z "$AGY" ] || [ ! -x "$AGY" ]; then echo \(agyNotFoundMarker) >&2; exit 127; fi
    CACHE="$HOME/Library/Caches/PlanMonitor-agy"
    /bin/mkdir -p "$CACHE" && /bin/chmod 700 "$CACHE" || exit 1

    # Runs agy once and saves its report and exit status.
    refresh() {
      WORK="$(/usr/bin/mktemp -d)" || return 1
      printf '#!/bin/sh\\nexit 1\\n' > "$WORK/open"
      /bin/cp "$WORK/open" "$WORK/xdg-open"
      /bin/chmod 755 "$WORK/open" "$WORK/xdg-open"
      (cd "$WORK" && exec /usr/bin/env PATH="$WORK:/usr/bin:/bin:/usr/sbin:/sbin" BROWSER="$WORK/open" AGY_CLI_DISABLE_AUTO_UPDATE=true \\
        "$AGY" -p /usage --output-format json) > "$CACHE/usage.$$.tmp" 2>/dev/null &
      echo $! > "$CACHE/agy.pid"
      wait $!
      rc=$?
      /bin/rm -f "$CACHE/agy.pid"
      /bin/rm -rf "$WORK"
      if [ "$rc" -eq 0 ]; then /bin/mv -f "$CACHE/usage.$$.tmp" "$CACHE/usage.json"; else /bin/rm -f "$CACHE/usage.$$.tmp" "$CACHE/usage.json"; fi
      echo "$rc" > "$CACHE/status.$$.tmp" && /bin/mv -f "$CACHE/status.$$.tmp" "$CACHE/status"
      return "$rc"
    }

    if [ "${1:-}" = "--refresh" ]; then
      refresh
      /bin/rm -f "$CACHE/pid"
      exit 0
    fi

    # A background run still going: leave it, unless it has hung for two minutes.
    running=0
    if [ -f "$CACHE/pid" ] && /bin/kill -0 "$(/bin/cat "$CACHE/pid")" 2>/dev/null; then
      if [ -n "$(/usr/bin/find "$CACHE/pid" -mmin -2 2>/dev/null)" ]; then running=1
      else
        # The waiting script first, so it can't record the kill as agy's result; then agy.
        /bin/kill "$(/bin/cat "$CACHE/pid")" 2>/dev/null
        /bin/kill "$(/bin/cat "$CACHE/agy.pid" 2>/dev/null)" 2>/dev/null
        /bin/rm -f "$CACHE/pid" "$CACHE/agy.pid"
      fi
    fi
    /usr/bin/find "$CACHE" -name '*.tmp' -mmin +5 -delete 2>/dev/null

    if [ -n "$(/usr/bin/find "$CACHE/status" -mmin -30 2>/dev/null)" ]; then
      # A recent result: hand it back and refresh it in the background.
      if [ "$running" -eq 0 ]; then
        /usr/bin/nohup /bin/sh "$0" --refresh </dev/null >/dev/null 2>&1 &
        echo $! > "$CACHE/pid"
      fi
      STATUS="$(/bin/cat "$CACHE/status" 2>/dev/null)"
      if [ "$STATUS" = 0 ] && [ -f "$CACHE/usage.json" ]; then /bin/cat "$CACHE/usage.json"; exit 0; fi
      exit "${STATUS:-1}"
    fi

    # Nothing recent (first run, or after a long sleep): run agy now.
    refresh
    rc=$?
    if [ "$rc" -eq 0 ]; then /bin/cat "$CACHE/usage.json"; fi
    exit "$rc"

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
