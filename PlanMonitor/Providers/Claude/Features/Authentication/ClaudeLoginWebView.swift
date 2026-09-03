//
//  ClaudeLoginWebView.swift
//  PlanTracker
//

import SwiftUI
import WebKit

struct ClaudeLoginWebView: NSViewRepresentable {
    let onSessionKeyExtracted: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Observe URL changes for SPA navigation
        context.coordinator.observeURL(webView: webView)

        let request = URLRequest(url: URL(string: "https://claude.ai/login")!)
        webView.load(request)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionKeyExtracted: onSessionKeyExtracted)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onSessionKeyExtracted: (String) -> Void
        private var hasExtractedSession = false
        private var urlObservation: NSKeyValueObservation?
        private var checkTimer: Timer?

        init(onSessionKeyExtracted: @escaping (String) -> Void) {
            self.onSessionKeyExtracted = onSessionKeyExtracted
        }

        deinit {
            urlObservation?.invalidate()
            checkTimer?.invalidate()
        }

        func observeURL(webView: WKWebView) {
            // Reset state for new login attempt
            hasExtractedSession = false
            urlObservation?.invalidate()
            checkTimer?.invalidate()

            // KVO observation for URL changes
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, change in
                guard let self, !self.hasExtractedSession else { return }
                if let url = change.newValue as? URL {
                    self.checkIfAuthenticated(webView: webView, url: url)
                }
            }

            // Also poll periodically for SPA changes that don't trigger KVO
            checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView, !self.hasExtractedSession else { return }
                if let url = webView.url {
                    self.checkIfAuthenticated(webView: webView, url: url)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasExtractedSession else { return }
            guard let url = webView.url else { return }
            checkIfAuthenticated(webView: webView, url: url)
        }

        private func checkIfAuthenticated(webView: WKWebView, url: URL) {
            guard !hasExtractedSession else { return }

            let urlString = url.absoluteString

            // Check if we're on a page that indicates successful login
            let isLoginPage = urlString.contains("/login") ||
                              urlString.contains("/oauth") ||
                              urlString.contains("/auth") ||
                              urlString.contains("accounts.google.com") ||
                              urlString.contains("isolated-segment")

            if !isLoginPage && urlString.contains("claude.ai") {
                extractAndSendCookies(webView: webView)
            }
        }

        private let allowedDomains = [
            "claude.ai"
        ]

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let host = url.host?.lowercased() else {
                decisionHandler(.cancel)
                return
            }

            let isAllowed = allowedDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }

            if isAllowed {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private func extractAndSendCookies(webView: WKWebView) {
            guard !hasExtractedSession else { return }

            checkTimer?.invalidate()

            let dataStore = webView.configuration.websiteDataStore
            dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.hasExtractedSession else { return }

                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                guard !claudeCookies.isEmpty else {
                    return
                }

                // Build cookie string
                let cookieString = claudeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

                self.hasExtractedSession = true

                // Clear WebView cookies to prevent duplicate Keychain entries
                for cookie in claudeCookies {
                    dataStore.httpCookieStore.delete(cookie)
                }

                DispatchQueue.main.async {
                    self.onSessionKeyExtracted(cookieString)
                }
            }
        }
    }
}
