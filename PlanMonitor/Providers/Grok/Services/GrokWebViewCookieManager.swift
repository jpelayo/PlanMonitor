import Foundation
import WebKit

actor GrokWebViewCookieManager {
    /// Looks in the named Grok store first (where the login WebView captured the session), then
    /// falls back to the default store.
    func extractSessionCookies() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                GrokWebsiteDataStore.makeStore().httpCookieStore.getAllCookies { cookies in
                    if let header = Self.cookieHeader(from: cookies) {
                        continuation.resume(returning: header)
                        return
                    }
                    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                        continuation.resume(returning: Self.cookieHeader(from: cookies))
                    }
                }
            }
        }
    }

    /// Removes grok.com / x.ai cookies and site data from both the default store and the named
    /// Grok store used by the login WebView and cookie minter.
    func clearSessionCookies() async {
        await Self.clearGrokData(in: { WKWebsiteDataStore.default() })
        await Self.clearGrokData(in: { GrokWebsiteDataStore.makeStore() })
    }

    private nonisolated static func clearGrokData(
        in makeStore: @escaping @Sendable () -> WKWebsiteDataStore
    ) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let dataStore = makeStore()
                dataStore.httpCookieStore.getAllCookies { cookies in
                    let grokCookies = cookies.filter { cookie in
                        let domain = cookie.domain.lowercased()
                        return domain.contains("grok.com") || domain.contains("x.ai")
                    }
                    let group = DispatchGroup()
                    for cookie in grokCookies {
                        group.enter()
                        dataStore.httpCookieStore.delete(cookie) {
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                            let grokRecords = records.filter {
                                $0.displayName.contains("grok.com") || $0.displayName.contains("x.ai")
                            }
                            dataStore.removeData(ofTypes: dataTypes, for: grokRecords) {
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
    }

    nonisolated static func cookieHeader(from cookies: [HTTPCookie]) -> String? {
        let now = Date()
        let grokCookies = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let isGrokDomain = domain.contains("grok.com") || domain.contains("x.ai")
            let isNotExpired = cookie.expiresDate == nil || cookie.expiresDate! > now
            return isGrokDomain && isNotExpired
        }
        let hasAuthCookie = grokCookies.contains { cookie in
            Self.isSessionCookieName(cookie.name)
        }
        guard hasAuthCookie else { return nil }
        return grokCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    nonisolated static func isSessionCookieName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered == "sso" || lowered == "sso-rw"
    }

    nonisolated static func httpCookies(from header: String) -> [HTTPCookie] {
        let domains = [".grok.com", "grok.com", ".x.ai", "x.ai", "accounts.x.ai", ".accounts.x.ai"]
        var cookies: [HTTPCookie] = []
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let divider = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<divider])
            let value = String(trimmed[trimmed.index(after: divider)...])
            guard !name.isEmpty else { continue }
            for domain in domains {
                if let cookie = HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: "/",
                    .secure: "TRUE"
                ]) {
                    cookies.append(cookie)
                }
            }
        }
        return cookies
    }

    nonisolated static func plantSessionCookies(_ header: String) async {
        let cookies = httpCookies(from: header)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let store = WKWebsiteDataStore.default().httpCookieStore
                let group = DispatchGroup()
                for cookie in cookies {
                    group.enter()
                    store.setCookie(cookie) {
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    continuation.resume()
                }
            }
        }
    }

    nonisolated static func cookieHeaderContainsSession(_ header: String) -> Bool {
        header.split(separator: ";").contains { part in
            let name = part.trimmingCharacters(in: .whitespaces).prefix { $0 != "=" }
            return isSessionCookieName(String(name))
        }
    }
}
