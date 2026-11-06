import AppKit
import os
import SwiftUI
import WebKit

/// x.ai's approval page in a throwaway web view. The user signs in and approves here; x.ai runs its
/// own sign-in, cookie chain and 2FA and comes back to the approval by itself (seen live on
/// 2026-11-06). Nothing is read from the pages and nothing is injected into them: success is the
/// token arriving at `GrokOIDCClient`'s poll, not anything this view sees.
struct GrokLoginWebView: NSViewRepresentable {
    let approvalURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A fresh, in-memory store per attempt: nothing is kept from one sign-in to the next.
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        if let defaultAgent = WKWebView().value(forKey: "userAgent") as? String,
           !defaultAgent.contains("Safari/") {
            webView.customUserAgent = defaultAgent + " Version/18.2 Safari/605.1.15"
        }
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.hostWebView = webView
        context.coordinator.start(approvalURL, in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopApprovalWatchdog()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var hostWebView: WKWebView?
        private var popupWebView: WKWebView?
        private var approvalURL: URL?
        private var approvalWatchdog: Timer?
        private var approvalReloads = 0
        private var stalledURL: String?
        private var stalledSince: Date?

        /// x.ai's own page can move itself to the account page instead of the approval, as it did
        /// on another Mac on 2026-10-29, leaving the approval out of sight while the app polls for
        /// it. After this long on such a page with nothing loading, the approval page is loaded
        /// again. A user decision; the approval-first walk of 2026-11-06 did not need it.
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

        /// Hosts allowed to perform the SSO cookie hop (`/set-cookie`): grok.com, x.ai and
        /// their subdomains (accounts.x.ai, auth.x.ai, ...), taken from `allowedDomains` — and
        /// cursor.com, whose hop x.ai's cookie chain runs between the password and 2FA. Cancelling
        /// it stops the chain, and 2FA never appears.
        private let cookieHopDomains = ["grok.com", "x.ai", "cursor.com"]

        deinit {
            approvalWatchdog?.invalidate()
        }

        // MARK: Approval page

        func start(_ url: URL, in webView: WKWebView) {
            approvalURL = url
            GrokLoginLog.log("window open on the approval page")
            webView.load(URLRequest(url: url))
            approvalWatchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.checkApprovalProgress(webView)
            }
        }

        private func checkApprovalProgress(_ webView: WKWebView) {
            guard let approvalURL, let url = webView.url else { return }
            let host = url.host?.lowercased() ?? ""
            if host == "x.ai" || host.hasSuffix(".x.ai"), url.path.lowercased().hasPrefix("/oauth2/device/done") {
                stopApprovalWatchdog()
                GrokLoginLog.log("approval done — watchdog off")
                return
            }
            // Any other page, or a page still loading, is the flow moving: the clock restarts.
            guard isOffTheFlow(url), !webView.isLoading else {
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
                GrokLoginLog.log("approval-watchdog gave up after \(Self.maxApprovalReloads) reloads")
                stopApprovalWatchdog()
                return
            }
            approvalReloads += 1
            stalledURL = nil
            stalledSince = nil
            GrokLoginLog.log(
                "approval page replaced by \(GrokLoginLog.redacted(url)) for \(Int(Self.approvalStallSeconds)) s"
                    + " — reloading (\(approvalReloads)/\(Self.maxApprovalReloads))"
            )
            webView.load(URLRequest(url: approvalURL))
        }

        func stopApprovalWatchdog() {
            approvalWatchdog?.invalidate()
            approvalWatchdog = nil
        }

        /// x.ai's account pages and the Grok app: places a signed-in user can land that lead
        /// nowhere from here.
        private func isOffTheFlow(_ url: URL) -> Bool {
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            if host == "grok.com" || host == "www.grok.com" { return true }
            guard host == "accounts.x.ai" else { return false }
            return path == "/" || path.isEmpty || path.hasPrefix("/account") || path.hasPrefix("/settings")
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            GrokLoginLog.log("nav-finish \(GrokLoginLog.redacted(webView.url))")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            GrokLoginLog.log("nav-fail \(GrokLoginLog.redacted(webView.url)) \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            GrokLoginLog.log("nav-fail-provisional \(GrokLoginLog.redacted(webView.url)) \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
        ) {
            GrokLoginLog.log("nav-redirect \(GrokLoginLog.redacted(webView.url))")
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
                GrokLoginLog.log("nav-\(frameKind)-CANCEL missing-url")
                decisionHandler(.cancel)
                return
            }
            // Every frame and every new window goes through the same allowlist.
            let allowed = isAllowed(url) || isCookieHop(url)
            GrokLoginLog.log("nav-\(frameKind)-\(allowed ? "allow" : "CANCEL") \(GrokLoginLog.redacted(url))")
            decisionHandler(allowed ? .allow : .cancel)
        }

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

        // MARK: Pop-ups and panels

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
                GrokLoginLog.log("popup-CANCEL \(GrokLoginLog.redacted(url))")
                return nil
            }
            GrokLoginLog.log("popup \(GrokLoginLog.redacted(navigationAction.request.url))")
            let popup = WKWebView(frame: host.bounds, configuration: configuration)
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
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            completionHandler()
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
    }
}

/// **Debug builds only.** Navigation lines for `log stream`, category `LoginNetwork`.
private enum GrokLoginLog {
#if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.infinitecontext.plantracker",
        category: "LoginNetwork"
    )

    /// `line` must already be redacted (see `redacted(_:)`).
    static func log(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }
#else
    static func log(_ line: String) {}
#endif

    /// Scheme, host and path only: the approval code and any other query or fragment values never
    /// reach a log, and a path segment long enough to be a one-time token is cut to its first four
    /// characters.
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
