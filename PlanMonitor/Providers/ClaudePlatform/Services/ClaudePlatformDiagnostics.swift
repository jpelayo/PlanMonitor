import Foundation
import os

/// **Debug builds only.** A running account of Claude-API's sign-in and polls for the Xcode
/// console, every line prefixed `[Claude-API]`, written so the first live sign-in answers the
/// questions nothing offline could (handoff §7g): which hosts the login page touches, what the
/// signed-in identity looks like, which cookies make a session, what each endpoint answers.
///
/// Never logged, by construction: a cookie *value*, the `Cookie` request header, a URL's query or
/// fragment (where magic-link tokens and OAuth codes live), an email address. In Release the body
/// of `log` is compiled out and its argument — an autoclosure — is never even evaluated.
nonisolated enum ClaudePlatformDiagnostics {
    #if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.infinitecontext.plantracker",
        category: "ClaudeAPI"
    )
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.notice("[Claude-API] \(text, privacy: .public)")
        #endif
    }

    /// `host/path` and nothing else — and any path segment long enough to be a one-time token
    /// (some flows put the code in the path, not the query) shortened to its first four characters.
    static func redacted(_ url: URL?) -> String {
        guard let url else { return "(no url)" }
        guard let host = url.host else { return url.scheme.map { "\($0):" } ?? "(no host)" }
        let path = url.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.count >= 20 ? $0.prefix(4) + "…" : $0 }
            .joined(separator: "/")
        return host + path
    }

    /// Cookie names, sorted and de-duplicated. Never values.
    static func names(_ cookies: [HTTPCookie]) -> String {
        "[" + Set(cookies.map(\.name)).sorted().joined(separator: ", ") + "]"
    }

    /// The names in a `Cookie:` header. Never values.
    static func names(inHeader header: String) -> String {
        "[" + ClaudePlatformClient.parseCookieHeader(header).keys.sorted().joined(separator: ", ") + "]"
    }

    /// The first eight characters of an id — enough to tell orgs apart in a log.
    static func shortID(_ id: String) -> String {
        String(id.prefix(8)) + "…"
    }

    /// Default org names embed the owner's address ("someone@example.com's Organization").
    static func scrubEmails(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.contains("@") ? "<email>" + ($0.hasSuffix("'s") ? "'s" : "") : String($0) }
            .joined(separator: " ")
    }

    /// The shape of a `/api/bootstrap` answer: keys, whether an email is present, and each
    /// membership's org (short id, name, capabilities). The email itself is never printed.
    static func describeBootstrap(_ json: Any) -> String {
        guard let object = json as? [String: Any] else { return "bootstrap: not a JSON object" }
        guard let account = object["account"] else {
            return "bootstrap: no `account` key; top-level keys \(object.keys.sorted())"
        }
        if account is NSNull { return "bootstrap: account is null (signed out)" }
        guard let account = account as? [String: Any] else { return "bootstrap: `account` is not an object" }

        let hasEmail = (account["email_address"] as? String) != nil || (account["email"] as? String) != nil
        let memberships = account["memberships"] as? [[String: Any]] ?? []
        let orgs = memberships.map { membership -> String in
            guard let org = membership["organization"] as? [String: Any] else {
                return "(membership without organization; keys \(membership.keys.sorted()))"
            }
            let id = (org["uuid"] as? String) ?? (org["id"] as? String) ?? "?"
            let name = scrubEmails(org["name"] as? String ?? "?")
            let capabilities = org["capabilities"] as? [String] ?? []
            return "\(shortID(id)) '\(name)' capabilities \(capabilities)"
        }
        return "bootstrap: account keys \(account.keys.sorted()); email present: \(hasEmail); "
            + "\(memberships.count) membership(s): \(orgs.joined(separator: " | "))"
    }

    /// Every figure a poll produced, so the cents reading and the null handling can be checked
    /// against what the console's own page shows.
    static func describe(_ snapshot: ClaudePlatformSnapshot) -> String {
        // The log always spells the code out, whatever the user picked for display.
        func money(_ value: Int?) -> String { value.map { snapshot.format($0, style: .codeAfter) } ?? "nil" }
        func date(_ value: Date?) -> String { value.map { ISO8601DateFormatter().string(from: $0) } ?? "nil" }
        let limits = snapshot.selfSelectedLimits
            .map { "\(money($0.amount)) \($0.action.rawValue)" }
            .joined(separator: ", ")
        let recharge = snapshot.autoRecharge.map {
            "\($0.isEnabled ? "on" : "off") target \(money($0.targetAmount)) threshold \(money($0.thresholdAmount))"
        } ?? "nil"
        return "poll: promo \(money(snapshot.promoRemaining)) left of \(money(snapshot.promoGranted)), "
            + "expires \(date(snapshot.promoExpiresAt)) '\(snapshot.promoName ?? "nil")' · "
            + "prepaid \(money(snapshot.prepaidRemaining)) · to be invoiced \(money(snapshot.pendingInvoice)) · "
            + "spend \(money(snapshot.spendUsed)) of enforced \(money(snapshot.enforcedSpendLimit)), "
            + "resets \(date(snapshot.spendResetsAt)) · limits [\(limits)] · auto-payment \(recharge) · "
            + "currency \(snapshot.currency ?? "not reported") exponent \(snapshot.exponent)"
            + (snapshot.currencyMismatch ? " · CURRENCY MISMATCH" : "")
    }
}
