import SwiftUI
import WebKit

/// The Claude Platform sign-in page, `https://platform.claude.com/login`, in an isolated web view.
///
/// Not a string swap of `ClaudeLoginWebView` — four things differ (plan §5.2):
///
/// 1. **The allowlist** comes from the login page's own `frame-src`, because `decidePolicyFor`
///    fires for iframes too: Cloudflare's and hCaptcha's challenge frames must load, or sign-in
///    silently never completes. The user solves any challenge themselves; this only declines to
///    cancel the frame. Every blocked host is recorded as a breadcrumb so the list can be
///    reconciled after the first real sign-in.
/// 2. **A `WKUIDelegate`**, which no other login view has, so a `window.open` loads here instead
///    of doing nothing.
/// 3. **Cookies are harvested by host, never by name** — the console's session cookie name is not
///    knowable from outside — and Cloudflare's edge cookies travel with them.
/// 4. **Success is an API probe, not a URL pattern.** The console is a client-side SPA whose URL
///    changes without navigation; the callback validates the cookies against the identity
///    endpoint and answers whether they are a session yet.
///
/// The store is `.nonPersistent()`: nothing is shared with any other provider, and closing the
/// window discards everything the page wrote.
struct ClaudePlatformLoginWebView: NSViewRepresentable {
    static let loginURL = URL(string: "https://platform.claude.com/login")!

    /// Answers whether the cookies are a signed-in session. Called again whenever the harvested
    /// set changes, until one is.
    let onSessionCookiesExtracted: (String) async -> Bool
    let onValidatingChange: (Bool) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.observe(webView: webView)

        webView.load(URLRequest(url: Self.loginURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionCookiesExtracted: onSessionCookiesExtracted, onValidatingChange: onValidatingChange)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let onSessionCookiesExtracted: (String) async -> Bool
        private let onValidatingChange: (Bool) -> Void
        private var checkTimer: Timer?
        private var isValidating = false
        private var isSignedIn = false
        /// The last set offered, so an unchanged jar is never probed twice.
        private var lastOfferedHeader: String?
        private var loggedBlockedHosts: Set<String> = []
        /// Debug diagnostics log only changes, not every one-second tick.
        private var lastLoggedURL: String?
        private var lastLoggedJar: String?

        init(
            onSessionCookiesExtracted: @escaping (String) async -> Bool,
            onValidatingChange: @escaping (Bool) -> Void
        ) {
            self.onSessionCookiesExtracted = onSessionCookiesExtracted
            self.onValidatingChange = onValidatingChange
        }

        deinit {
            checkTimer?.invalidate()
        }

        func observe(webView: WKWebView) {
            checkTimer?.invalidate()
            // The page is an SPA: sign-in completes without a navigation, so the jar is checked
            // on a timer as well as after each load.
            checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.logURLChange(webView.url)
                self.harvestCookies(from: webView)
            }
            ClaudePlatformDiagnostics.log("login window opened at \(ClaudePlatformDiagnostics.redacted(ClaudePlatformLoginWebView.loginURL))")
        }

        func stop() {
            checkTimer?.invalidate()
            checkTimer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ClaudePlatformDiagnostics.log("login page loaded: \(ClaudePlatformDiagnostics.redacted(webView.url))")
            harvestCookies(from: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            ClaudePlatformDiagnostics.log("login load failed before commit: \(Self.describe(error))")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            ClaudePlatformDiagnostics.log("login load failed: \(Self.describe(error))")
        }

        /// The SPA changes its URL without navigating; this catches each change once.
        private func logURLChange(_ url: URL?) {
            let redacted = ClaudePlatformDiagnostics.redacted(url)
            guard redacted != lastLoggedURL else { return }
            lastLoggedURL = redacted
            ClaudePlatformDiagnostics.log("login url is now \(redacted)")
        }

        private static func describe(_ error: Error) -> String {
            let nsError = error as NSError
            return "\(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)"
        }

        // MARK: Allowlist

        /// From the login page's `frame-src` (plan §5.0). Exact host or a subdomain of one — never
        /// a substring match.
        private let allowedDomains = [
            "platform.claude.com",
            "claude.ai",
            "challenges.cloudflare.com",
            "hcaptcha.com",
            "accounts.google.com",
            "google.com",
            "gstatic.com"
        ]

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Blank and inline frames load nothing from the network.
            if ["about", "blob", "data"].contains(url.scheme?.lowercased() ?? "") {
                decisionHandler(.allow)
                return
            }
            guard let host = url.host?.lowercased() else {
                decisionHandler(.cancel)
                return
            }

            let isAllowed = allowedDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }

            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            ClaudePlatformDiagnostics.log(
                "login \(isAllowed ? "allow" : "BLOCK") "
                    + (isMainFrame ? "page \(ClaudePlatformDiagnostics.redacted(url))" : "frame \(host)")
            )

            if isAllowed {
                decisionHandler(.allow)
            } else {
                if loggedBlockedHosts.insert(host).inserted {
                    AppRuntimeState.recordBreadcrumb("provider-claudeapi-login-blocked-\(host)")
                }
                decisionHandler(.cancel)
            }
        }

        // MARK: Popups

        /// `window.open` lands in this same view, through the allowlist above.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                ClaudePlatformDiagnostics.log("login popup redirected into the window: \(ClaudePlatformDiagnostics.redacted(url))")
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: Harvesting

        private func harvestCookies(from webView: WKWebView) {
            guard !isSignedIn, !isValidating else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.isSignedIn, !self.isValidating else { return }

                let now = Date()
                let consoleCookies = cookies.filter { cookie in
                    Self.isConsoleDomain(cookie.domain) && (cookie.expiresDate.map { $0 > now } ?? true)
                }
                self.logJar(cookies, console: consoleCookies)

                // Cookies exist before anyone signs in; only offer a set that carries something
                // that could be a session, and only once per distinct set.
                guard consoleCookies.contains(where: { Self.isPlausibleSessionCookie($0.name) }) else { return }

                let header = consoleCookies
                    .sorted { $0.name < $1.name }
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                guard header != self.lastOfferedHeader else { return }
                self.lastOfferedHeader = header

                let plausible = consoleCookies.filter { Self.isPlausibleSessionCookie($0.name) }
                ClaudePlatformDiagnostics.log(
                    "offering \(consoleCookies.count) cookies for validation \(ClaudePlatformDiagnostics.names(consoleCookies)); "
                        + "plausible session cookie(s) \(ClaudePlatformDiagnostics.names(plausible))"
                )

                self.isValidating = true
                self.onValidatingChange(true)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let isSessionReady = await self.onSessionCookiesExtracted(header)
                    self.isValidating = false
                    self.onValidatingChange(false)
                    ClaudePlatformDiagnostics.log(isSessionReady
                        ? "candidate ACCEPTED — signed in, closing the window"
                        : "candidate rejected — not a session yet, still watching")
                    if isSessionReady {
                        self.isSignedIn = true
                        self.stop()
                    }
                }
            }
        }

        /// The jar's cookie names by domain, whenever they change — which cookie appears at the
        /// moment sign-in completes is how the session cookie's name gets learned. Names only.
        private func logJar(_ all: [HTTPCookie], console: [HTTPCookie]) {
            let byDomain = Dictionary(grouping: all, by: \.domain)
                .sorted { $0.key < $1.key }
                .map { "\($0.key) \(ClaudePlatformDiagnostics.names($0.value))" }
                .joined(separator: " · ")
            guard byDomain != lastLoggedJar else { return }
            lastLoggedJar = byDomain
            ClaudePlatformDiagnostics.log("cookie jar now (names only): \(byDomain.isEmpty ? "empty" : byDomain); console-domain cookies: \(console.count)")
        }

        /// `platform.claude.com`, `.claude.com` or `claude.com`. Never `claude.ai`: those are the
        /// Claude provider's cookies, and an exact-host match is what keeps this filter from
        /// reaching them — not the accident that one spelling does not contain the other.
        static func isConsoleDomain(_ domain: String) -> Bool {
            let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == "claude.com" || host.hasSuffix(".claude.com")
        }

        /// Codex's test, minus the names measured on the console *before* sign-in.
        static func isPlausibleSessionCookie(_ name: String) -> Bool {
            let name = name.lowercased()
            guard !preSignInCookieNames.contains(name), !name.contains("csrf"), !name.contains("xsrf") else {
                return false
            }
            return name.contains("session") || name.contains("auth") || name.contains("token")
        }

        private static let preSignInCookieNames: Set<String> = ["activitysessionid"]
    }
}
