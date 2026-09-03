import Foundation
import WebKit

@MainActor
final class GrokOIDCCookieMinter: NSObject, WKNavigationDelegate {
    static let shared = GrokOIDCCookieMinter()

    private var webView: WKWebView?

    func approve(url: URL, cookies: String) async {
        let configuration = WKWebViewConfiguration()
        // A fresh, in-memory store per attempt: the approval page only ever sees the grok.com
        // session planted for it, never a stale auth.x.ai session from an earlier attempt.
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let store = configuration.websiteDataStore
        for cookie in GrokWebViewCookieManager.httpCookies(from: cookies) {
            await store.httpCookieStore.setCookie(cookie)
        }
        webView.load(URLRequest(url: url))

        for _ in 0..<8 {
            try? await Task.sleep(for: .seconds(1.5))
            _ = try? await webView.evaluateJavaScript(Self.approveScript)
        }
    }

    func tearDown() {
        webView?.navigationDelegate = nil
        webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            _ = try? await webView.evaluateJavaScript(Self.approveScript)
        }
    }

    private static let approveScript = """
    (function() {
      const labels = /approve|allow|autoriz|continuar|accept|confirm|permit|conectar|connect/i;
      const nodes = Array.from(document.querySelectorAll('button, input[type=submit], a[role=button], a'));
      const match = nodes.find((el) => labels.test((el.innerText || el.value || el.getAttribute('aria-label') || '').trim()));
      if (match) match.click();
    })();
    """
}
