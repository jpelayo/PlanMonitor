import AppKit
import os
import SwiftUI
import WebKit

struct GrokLoginWebView: NSViewRepresentable {
    var followUpURL: URL?
    var seedCookies: String?
    let onSessionCookiesExtracted: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A fresh, in-memory store per attempt: the approval page only ever sees the grok.com
        // session planted for it, never a stale auth.x.ai session from an earlier attempt.
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let networkProbe = WKUserScript(
            source: LoginNetworkProbe.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(networkProbe)
        configuration.userContentController.add(context.coordinator, name: LoginNetworkProbe.messageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
#if DEBUG
        webView.isInspectable = true
#endif
        if let defaultAgent = WKWebView().value(forKey: "userAgent") as? String,
           !defaultAgent.contains("Safari/") {
            webView.customUserAgent = defaultAgent + " Version/18.2 Safari/605.1.15"
        }
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.hostWebView = webView
        context.coordinator.observeURL(webView: webView)
        context.coordinator.plantCookies(seedCookies, in: webView) {
            let start = context.coordinator.lastFollowUpURL
                ?? URL(string: "https://accounts.x.ai/sign-in?redirect=https://grok.com")!
            webView.load(URLRequest(url: start))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let seedCookies, !context.coordinator.didPlantSeedCookies {
            context.coordinator.plantCookies(seedCookies, in: nsView) {
                if let followUpURL {
                    context.coordinator.loadFollowUp(followUpURL, in: nsView)
                }
            }
            return
        }
        guard let followUpURL, context.coordinator.lastFollowUpURL != followUpURL else { return }
        context.coordinator.loadFollowUp(followUpURL, in: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionCookiesExtracted: onSessionCookiesExtracted)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let onSessionCookiesExtracted: (String) -> Void
        var lastFollowUpURL: URL?
        var didPlantSeedCookies = false
        weak var hostWebView: WKWebView?
        private var popupWebView: WKWebView?
        private var hasExtractedSession = false
        private var didVisitAuthPage = false
        private var didVisitTwoFactor = false
        private var urlObservation: NSKeyValueObservation?
        private var checkTimer: Timer?
        /// Debug log only: the last stage line and cookie-name set written, so each is logged
        /// when it changes rather than on every one-second check.
        private var lastLoggedStage: String?
        private var lastLoggedJar: String?
        private var approvalWatchdog: Timer?
        private var isApprovalDone = false
        private var approvalReloads = 0
        private var stalledURL: String?
        private var stalledSince: Date?

        /// x.ai's own page can move itself to the account page just after the approval page was
        /// requested — a race, seen on another Mac on 2026-10-29 — leaving the approval out of
        /// sight while the app polls for it. After this long on the account page with nothing
        /// loading, the approval page is loaded again.
        private static let approvalStallSeconds: TimeInterval = 5
        /// Then the watchdog gives up, so a flow broken some other way can't loop.
        private static let maxApprovalReloads = 3

        private let allowedDomains = [
            "grok.com",
            "grokusercontent.com",
            "grokipedia.com",
            "x.ai",
            "accounts.x.ai",
            "auth.x.ai",
            "api.x.ai",
            "console.x.ai",
            "status.x.ai",
            "x.com",
            "twitter.com",
            "google.com",
            "gstatic.com",
            "googleusercontent.com",
            "apple.com",
            "appleid.apple.com",
            "cloudflare.com",
            "challenges.cloudflare.com",
            "cloudflareinsights.com",
            "cookielaw.org",
            "onetrust.com",
            "stapecdn.com",
            "appsflyersdk.com",
            "sentry.io"
        ]

        init(onSessionCookiesExtracted: @escaping (String) -> Void) {
            self.onSessionCookiesExtracted = onSessionCookiesExtracted
            LoginNetworkProbe.log("probe-start")
        }

        deinit {
            urlObservation?.invalidate()
            checkTimer?.invalidate()
            approvalWatchdog?.invalidate()
        }

        // MARK: Approval page

        /// The only place the approval page is loaded, so the watchdog is always armed with it.
        func loadFollowUp(_ url: URL, in webView: WKWebView) {
            lastFollowUpURL = url
            webView.load(URLRequest(url: url))
            armApprovalWatchdog(webView)
        }

        /// Its own timer: `checkTimer` stops once the session is taken.
        private func armApprovalWatchdog(_ webView: WKWebView) {
            guard approvalWatchdog == nil, !isApprovalDone else { return }
            LoginNetworkProbe.log("approval-watchdog armed")
            approvalWatchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.checkApprovalProgress(webView)
            }
        }

        private func checkApprovalProgress(_ webView: WKWebView) {
            guard let followUp = lastFollowUpURL, let url = webView.url else { return }
            let host = url.host?.lowercased() ?? ""
            if host == "x.ai" || host.hasSuffix(".x.ai"), url.path.lowercased().hasPrefix("/oauth2/device/done") {
                isApprovalDone = true
                stopApprovalWatchdog()
                LoginNetworkProbe.log("approval done — watchdog off")
                return
            }
            // Any other page, or a page still loading, is the flow moving: the clock restarts.
            guard isAccountHome(url), !webView.isLoading else {
                stalledURL = nil
                stalledSince = nil
                return
            }
            let current = url.absoluteString
            guard current == stalledURL, let since = stalledSince else {
                stalledURL = current
                stalledSince = Date()
                return
            }
            guard Date().timeIntervalSince(since) >= Self.approvalStallSeconds else { return }
            guard approvalReloads < Self.maxApprovalReloads else {
                LoginNetworkProbe.log("approval-watchdog gave up after \(Self.maxApprovalReloads) reloads")
                stopApprovalWatchdog()
                return
            }
            approvalReloads += 1
            stalledURL = nil
            stalledSince = nil
            LoginNetworkProbe.log(
                "approval page replaced by \(LoginNetworkProbe.redacted(url)) for \(Int(Self.approvalStallSeconds)) s"
                    + " — reloading (\(approvalReloads)/\(Self.maxApprovalReloads))"
            )
            webView.load(URLRequest(url: followUp))
        }

        private func stopApprovalWatchdog() {
            approvalWatchdog?.invalidate()
            approvalWatchdog = nil
        }

        func observeURL(webView: WKWebView) {
            hasExtractedSession = false
            didVisitAuthPage = false
            urlObservation?.invalidate()
            checkTimer?.invalidate()

            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                guard let self, !self.hasExtractedSession, let url = webView.url else { return }
                self.checkIfAuthenticated(webView: webView, url: url)
            }

            checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView, !self.hasExtractedSession else { return }
                self.checkIfAuthenticated(webView: webView, url: webView.url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            LoginNetworkProbe.log("nav-finish \(LoginNetworkProbe.redacted(webView.url))")
            guard !hasExtractedSession, let url = webView.url else { return }
            checkIfAuthenticated(webView: webView, url: url)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            LoginNetworkProbe.log("nav-fail \(LoginNetworkProbe.redacted(webView.url)) \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            LoginNetworkProbe.log("nav-fail-provisional \(LoginNetworkProbe.redacted(webView.url)) \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
        ) {
            LoginNetworkProbe.log("nav-redirect \(LoginNetworkProbe.redacted(webView.url))")
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == LoginNetworkProbe.messageName else { return }
            LoginNetworkProbe.log("js \(LoginNetworkProbe.describe(message.body))")
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let host = hostWebView else {
                return nil
            }
            if let url = navigationAction.request.url, !isAllowed(url), !isCookieHop(url) {
                LoginNetworkProbe.log("popup-CANCEL \(LoginNetworkProbe.redacted(url))")
                return nil
            }
            LoginNetworkProbe.log("popup \(LoginNetworkProbe.redacted(navigationAction.request.url))")
            let popup = WKWebView(frame: host.bounds, configuration: configuration)
#if DEBUG
            popup.isInspectable = true
#endif
            popup.autoresizingMask = [.width, .height]
            popup.navigationDelegate = self
            popup.uiDelegate = self
            host.addSubview(popup)
            popupWebView = popup
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard webView == popupWebView else { return }
            webView.removeFromSuperview()
            popupWebView = nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            presentAlert(message: message, completion: completionHandler)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: String(localized: "OK"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: String(localized: "OK"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            let field = NSTextField(string: defaultText ?? "")
            field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
            alert.accessoryView = field
            if alert.runModal() == .alertFirstButtonReturn {
                completionHandler(field.stringValue)
            } else {
                completionHandler(nil)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let frameKind: String
            if let frame = navigationAction.targetFrame {
                frameKind = frame.isMainFrame ? "main" : "iframe"
            } else {
                frameKind = "blank"
            }
            guard let url = navigationAction.request.url else {
                LoginNetworkProbe.log("nav-\(frameKind)-CANCEL missing-url")
                decisionHandler(.cancel)
                return
            }
            // Every frame and every new window goes through the same allowlist.
            let allowed = isAllowed(url) || isCookieHop(url)
            LoginNetworkProbe.log("nav-\(frameKind)-\(allowed ? "allow" : "CANCEL") \(LoginNetworkProbe.redacted(url))")
            decisionHandler(allowed ? .allow : .cancel)
        }

        private func presentAlert(message: String, completion: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            completion()
        }

        /// Hosts allowed to perform the SSO cookie hop (`/set-cookie`): grok.com, x.ai and
        /// their subdomains (accounts.x.ai, auth.x.ai, ...), taken from `allowedDomains` — and
        /// cursor.com, whose hop x.ai's cookie chain runs after the password since 2026-10-29.
        /// Cancelling it stopped the chain before 2FA. Its cookies stay in this throwaway store:
        /// `cookieHeader(from:)` keeps only grok.com and x.ai ones.
        private let cookieHopDomains = ["grok.com", "x.ai", "cursor.com"]

        private func isCookieHop(_ url: URL) -> Bool {
            guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
            guard cookieHopDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return false }
            return url.path.lowercased().contains("/set-cookie")
        }

        private func isAllowed(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "data", "blob"].contains(scheme) {
                return true
            }
            guard let host = url.host?.lowercased() else {
                return false
            }
            return allowedDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }
        }

        private func checkIfAuthenticated(webView: WKWebView, url: URL?) {
            guard !hasExtractedSession else { return }
            let stage = loginStage(for: url)
            // Once per change, not once a second.
            let stageLine = "stage=\(stage) url=\(LoginNetworkProbe.redacted(url))"
            if stageLine != lastLoggedStage {
                lastLoggedStage = stageLine
                LoginNetworkProbe.log(stageLine)
            }
            switch stage {
            case .signIn, .identityProvider:
                didVisitAuthPage = true
                inspectPageForCompletion(webView)
            case .cookieHop:
                didVisitAuthPage = true
            case .twoFactor:
                didVisitAuthPage = true
                didVisitTwoFactor = true
            case .unknown:
                inspectPageForCompletion(webView)
            case .complete:
                guard didVisitAuthPage else { return }
                if didVisitTwoFactor || isGrokAppHome(url) {
                    extractAndSendCookies(webView: hostWebView ?? webView)
                }
            }
        }

        private func inspectPageForCompletion(_ webView: WKWebView) {
            webView.evaluateJavaScript(Self.twoFactorProbeScript) { [weak self] result, _ in
                guard let self, !self.hasExtractedSession else { return }
                if (result as? Bool) == true {
                    self.didVisitTwoFactor = true
                    self.didVisitAuthPage = true
                    LoginNetworkProbe.log("stage=twoFactor source=dom")
                    return
                }
                webView.evaluateJavaScript(Self.accountHomeProbeScript) { accountResult, _ in
                    let url = webView.url
                    let stage = self.loginStage(for: url)
                    // The sign-in page itself reads "tu cuenta" now (2026-10-29): before 2FA that
                    // text on a sign-in page proves nothing, and a hop is never a finish.
                    let onAccountHome = ((accountResult as? Bool) ?? false)
                        && stage != .cookieHop
                        && (stage != .signIn || self.didVisitTwoFactor)
                    if onAccountHome {
                        LoginNetworkProbe.log("stage=complete source=dom-account")
                    }
                    let finished = stage == .complete || onAccountHome
                    guard self.didVisitAuthPage, finished else { return }
                    guard self.didVisitTwoFactor || self.isGrokAppHome(url) || onAccountHome else { return }
                    LoginNetworkProbe.log("login-complete url=\(LoginNetworkProbe.redacted(url)) 2fa=\(self.didVisitTwoFactor)")
                    self.extractAndSendCookies(webView: self.hostWebView ?? webView)
                }
            }
        }

        private enum LoginStage: String {
            case signIn
            case identityProvider
            case cookieHop
            case twoFactor
            case complete
            case unknown
        }

        private func loginStage(for url: URL?) -> LoginStage {
            guard let url else { return .unknown }
            if isCookieHop(url) || isAuthCookieHost(url) || isCookieChain(url) {
                return .cookieHop
            }
            if isTwoFactorPage(url) {
                return .twoFactor
            }
            if isSignInPage(url) {
                return .signIn
            }
            if isExternalIdP(url) {
                return .identityProvider
            }
            if isGrokAppHome(url) || isAccountHome(url) {
                return .complete
            }
            return .unknown
        }

        private func isGrokAppHome(_ url: URL?) -> Bool {
            guard let host = url?.host?.lowercased() else { return false }
            return host == "grok.com" || host == "www.grok.com"
        }

        private func isAccountHome(_ url: URL) -> Bool {
            let host = url.host?.lowercased() ?? ""
            guard host == "accounts.x.ai" else { return false }
            if isSignInPage(url) || isTwoFactorPage(url) { return false }
            let path = url.path.lowercased()
            return path == "/" || path.isEmpty || path.hasPrefix("/account") || path.hasPrefix("/settings")
        }

        /// `accounts.x.ai/cookie-chain`: the page x.ai shows after the password (since
        /// 2026-10-29), walking the session through each sibling site's `/set-cookie`. Its text
        /// reads like the account page, but the session is not finished there.
        private func isCookieChain(_ url: URL) -> Bool {
            let host = url.host?.lowercased() ?? ""
            guard host == "x.ai" || host.hasSuffix(".x.ai") else { return false }
            return url.path.lowercased().hasPrefix("/cookie-chain")
        }

        private func isAuthCookieHost(_ url: URL) -> Bool {
            let host = url.host?.lowercased() ?? ""
            return host.hasPrefix("auth.")
        }

        private func isSignInPage(_ url: URL) -> Bool {
            let value = url.absoluteString.lowercased()
            return value.contains("/sign-in")
                || value.contains("/signin")
                || value.contains("/login")
                || value.contains("/password")
                || value.contains("email=true")
        }

        private func isTwoFactorPage(_ url: URL) -> Bool {
            let value = url.absoluteString.lowercased()
            return value.contains("/verify")
                || value.contains("/verifica")
                || value.contains("/2fa")
                || value.contains("/mfa")
                || value.contains("two-factor")
                || value.contains("two_factor")
                || value.contains("/otp")
        }

        private func isExternalIdP(_ url: URL) -> Bool {
            let host = url.host?.lowercased() ?? ""
            return host.contains("accounts.google.com")
                || host.contains("appleid.apple.com")
                || host == "x.com"
                || host.hasSuffix(".x.com")
                || host.contains("twitter.com")
        }

        private static let accountHomeProbeScript = """
        (function() {
          const text = ((document.body && document.body.innerText) || '') + ' ' + document.title;
          return /tu cuenta|your account|administra la informaci|manage your account/i.test(text);
        })()
        """

        private static let twoFactorProbeScript = """
        (function() {
          const text = ((document.body && document.body.innerText) || '') + ' ' + document.title;
          return /verifica tu cuenta|verify your account|segundo factor|second factor|two-factor|autenticaci[oó]n de dos|2fa/i.test(text);
        })()
        """

        func plantCookies(_ header: String?, in webView: WKWebView, then work: @escaping () -> Void) {
            guard let header, GrokWebViewCookieManager.cookieHeaderContainsSession(header) else {
                work()
                return
            }
            didPlantSeedCookies = true
            let cookies = GrokWebViewCookieManager.httpCookies(from: header)
            let store = webView.configuration.websiteDataStore.httpCookieStore
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main, execute: work)
        }

        private func extractAndSendCookies(webView: WKWebView) {
            guard !hasExtractedSession else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasExtractedSession else { return }
                // Which hop set which session: names by domain, whenever they change.
                let jar = LoginNetworkProbe.cookieNames(cookies)
                if jar != self.lastLoggedJar {
                    self.lastLoggedJar = jar
                    LoginNetworkProbe.log("grab attempt, cookie names by domain: \(jar)")
                }
                guard let cookieString = GrokWebViewCookieManager.cookieHeader(from: cookies) else { return }
                self.hasExtractedSession = true
                self.checkTimer?.invalidate()
                DispatchQueue.main.async {
                    self.onSessionCookiesExtracted(cookieString)
                }
            }
        }
    }
}

private enum LoginNetworkProbe {
    static let messageName = "networkLog"
#if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.infinitecontext.plantracker",
        category: "LoginNetwork"
    )

    static let script = """
    (function() {
      const send = (payload) => {
        if (payload && typeof payload.url === 'string') {
          payload.url = payload.url.split('#')[0].split('?')[0];
        }
        try { webkit.messageHandlers.networkLog.postMessage(payload); } catch (e) {}
      };
      const origFetch = window.fetch;
      window.fetch = function() {
        const input = arguments[0];
        const url = (typeof input === 'string') ? input : (input && input.url) ? input.url : String(input);
        const method = (arguments[1] && arguments[1].method) || (input && input.method) || 'GET';
        send({kind:'fetch', method: String(method), url: String(url)});
        return origFetch.apply(this, arguments).then(function(r) {
          send({kind:'fetch-done', method: String(method), url: String(url), status: r.status});
          return r;
        }).catch(function(err) {
          send({kind:'fetch-fail', method: String(method), url: String(url), error: String(err)});
          throw err;
        });
      };
      const origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__ptMethod = method;
        this.__ptURL = url;
        return origOpen.apply(this, arguments);
      };
      const origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function() {
        const xhr = this;
        send({kind:'xhr', method: String(xhr.__ptMethod || 'GET'), url: String(xhr.__ptURL || '')});
        xhr.addEventListener('loadend', function() {
          send({kind:'xhr-done', method: String(xhr.__ptMethod || 'GET'), url: String(xhr.__ptURL || ''), status: xhr.status});
        });
        return origSend.apply(this, arguments);
      };
    })();
    """

    /// `line` must already be redacted (see `redacted(_:)` / `describe(_:)`). Public so `log
    /// stream` can follow a supervised sign-in, as Claude-API's diagnostics do; Debug builds only.
    static func log(_ line: String) {
        logger.notice("\(line, privacy: .public)")
        Task { @MainActor in
            GrokLoginNetworkLogStore.shared.append(line)
        }
    }

    /// Renders a message body from the page probe with any `url` field redacted.
    static func describe(_ body: Any) -> String {
        guard var dictionary = body as? [String: Any] else {
            return String(describing: body)
        }
        if let url = dictionary["url"] as? String {
            dictionary["url"] = redacted(URL(string: url))
        }
        return dictionary
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    /// Cookie names grouped by domain, sorted. Never a value.
    static func cookieNames(_ cookies: [HTTPCookie]) -> String {
        let byDomain: [String: [HTTPCookie]] = Dictionary(grouping: cookies) { $0.domain.lowercased() }
        let rows: [String] = byDomain.keys.sorted().map { (domain: String) -> String in
            let names: [String] = Set((byDomain[domain] ?? []).map(\.name)).sorted()
            return "\(domain) [\(names.joined(separator: ", "))]"
        }
        return rows.isEmpty ? "empty" : rows.joined(separator: " · ")
    }
#else
    static let script = ""
    static func log(_ line: String) {}
    static func describe(_ body: Any) -> String { "" }
    static func cookieNames(_ cookies: [HTTPCookie]) -> String { "" }
#endif

    /// Scheme, host and path only: OIDC `code=` / `state=` and any other query or fragment
    /// values never reach a log, and a path segment long enough to be a one-time token is cut
    /// to its first four characters.
    static func redacted(_ url: URL?) -> String {
        guard let url else { return "nil" }
        let path = url.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { (segment: Substring) -> String in
                segment.count >= 20 ? String(segment.prefix(4)) + "…" : String(segment)
            }
            .joined(separator: "/")
        guard let scheme = url.scheme, let host = url.host else {
            return url.scheme.map { "\($0):\(path)" } ?? path
        }
        return "\(scheme)://\(host)\(path)"
    }
}
