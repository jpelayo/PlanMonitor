//
//  ClaudeWebViewCookieManager.swift
//  PlanTracker
//

import Foundation
import WebKit

actor ClaudeWebViewCookieManager {

    /// Extracts Claude session cookies from WKWebsiteDataStore
    func extractSessionCookies() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }

                    guard !claudeCookies.isEmpty else {
                        continuation.resume(returning: nil)
                        return
                    }

                    // Build cookie string for API requests
                    let cookieString = claudeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    continuation.resume(returning: cookieString)
                }
            }
        }
    }

    /// Clears all Claude-related cookies from WKWebsiteDataStore
    func clearSessionCookies() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let dataStore = WKWebsiteDataStore.default()

                // First, remove cookies
                dataStore.httpCookieStore.getAllCookies { cookies in
                    let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }

                    let group = DispatchGroup()
                    for cookie in claudeCookies {
                        group.enter()
                        dataStore.httpCookieStore.delete(cookie) {
                            group.leave()
                        }
                    }

                    group.notify(queue: .main) {
                        // Also clear website data
                        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                            let claudeRecords = records.filter { $0.displayName.contains("claude.ai") }
                            dataStore.removeData(ofTypes: dataTypes, for: claudeRecords) {
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
    }
}
