import Foundation

/// Process-wide URL cache policy. Every provider client disables its own cache, so the
/// shared cache only ever holds WebKit-adjacent residue; it is emptied once at launch and
/// flushed on sign-out. Nothing here is provider-specific.
enum CacheJanitor {
    /// Called exactly once, from the composition root.
    static func prepareForLaunch() {
        let emptyCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = emptyCache
    }

    /// Safe to call from any provider's sign-out: flushes, never replaces the instance
    /// sessions already hold.
    static func cleanupTransientCaches(reason _: String) {
        URLCache.shared.removeAllCachedResponses()
    }
}
