//
//  CodexLoginWebView.swift
//  PlanTracker
//

import SwiftUI
import WebKit

struct CodexLoginWebView: NSViewRepresentable {
    let onSessionCookiesExtracted: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Observe URL changes for SPA navigation
        context.coordinator.observeURL(webView: webView)

        let request = URLRequest(url: URL(string: "https://chatgpt.com/auth/login")!)
        webView.load(request)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionCookiesExtracted: onSessionCookiesExtracted)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onSessionCookiesExtracted: (String) -> Void
        private var hasExtractedSession = false
        private var urlObservation: NSKeyValueObservation?
        private var checkTimer: Timer?

        init(onSessionCookiesExtracted: @escaping (String) -> Void) {
            self.onSessionCookiesExtracted = onSessionCookiesExtracted
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

            let isOpenAIPage = urlString.contains("chatgpt.com") || urlString.contains("chat.openai.com")
            if !isLoginPage && isOpenAIPage {
                extractAndSendCookies(webView: webView)
            }
        }

        private let allowedDomains = [
            "chatgpt.com",
            "chat.openai.com",
            "auth.openai.com",
            "openai.com",
            "oaistatic.com",
            "oaiusercontent.com",
            "google.com",
            "googleusercontent.com",
            "gstatic.com"
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

                let openAICookies = cookies.filter { cookie in
                    let isOpenAIDomain = cookie.domain.contains("chatgpt.com")
                        || cookie.domain.contains("openai.com")
                        || cookie.domain.contains("chat.openai.com")
                    let isNotExpired = cookie.expiresDate == nil || cookie.expiresDate! > Date()
                    return isOpenAIDomain && isNotExpired
                }
                guard !openAICookies.isEmpty else {
                    return
                }

                let likelyAuthCookies = openAICookies.filter { cookie in
                    let name = cookie.name.lowercased()
                    return name.contains("session")
                        || name.contains("auth")
                        || name.contains("token")
                }
                guard !likelyAuthCookies.isEmpty else {
                    return
                }

                // Build cookie string
                let cookieString = openAICookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

                self.hasExtractedSession = true

                DispatchQueue.main.async {
                    self.onSessionCookiesExtracted(cookieString)
                }
            }
        }
    }
}
