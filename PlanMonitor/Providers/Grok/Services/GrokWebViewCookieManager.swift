import Foundation
import WebKit

/// Sign-out only. Grok's sign-in takes no cookies any more; this clears what older builds left in
/// the default store and the named Grok store.
actor GrokWebViewCookieManager {
    /// Removes grok.com / x.ai cookies and site data from both stores.
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
}
