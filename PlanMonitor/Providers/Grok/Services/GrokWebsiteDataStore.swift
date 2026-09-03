import Foundation
import WebKit

/// The single, stable on-disk `WKWebsiteDataStore` shared by the Grok login WebView and the
/// OIDC cookie minter. Using one fixed identifier (instead of a fresh random one per WebView)
/// means sign-out can find and delete every cookie those WebViews wrote.
nonisolated enum GrokWebsiteDataStore {
    static let identifier = UUID(uuidString: "6E1F3C2A-9B47-4D58-A1C3-2F7E8D5B0C94")!

    static func makeStore() -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: identifier)
    }

    /// Deletes the named store from disk. A missing store (never created, or already removed)
    /// is not an error for our purposes, so every failure is swallowed.
    static func removeAll() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in
                    continuation.resume()
                }
            }
        }
    }
}
