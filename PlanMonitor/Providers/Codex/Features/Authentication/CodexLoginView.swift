//
//  CodexLoginView.swift
//  PlanTracker
//

import SwiftUI

struct CodexLoginView: View {
    let onSessionCookiesExtracted: (String) async -> Bool
    @State private var webViewID = UUID()
    @State private var isValidating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Sign in to Codex"))
                    .font(.headline)

                Spacer()

                Button(String(localized: "Cancel")) {
                    WindowRouter.shared.close(.loginCodex)
                }
                .buttonStyle(.plain)
                .disabled(isValidating)
            }
            .padding()
            .background(.bar)

            if isValidating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Validating session...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            CodexLoginWebView(onSessionCookiesExtracted: { sessionCookies in
                guard !isValidating else { return }
                isValidating = true

                Task {
                    let isAuthenticated = await onSessionCookiesExtracted(sessionCookies)
                    await MainActor.run {
                        isValidating = false
                        if isAuthenticated {
                            WindowRouter.shared.close(.loginCodex)
                        } else {
                            // Reset webview state so user can retry if we captured non-auth cookies.
                            webViewID = UUID()
                        }
                    }
                }
            })
            .id(webViewID)
        }
        .frame(width: 480, height: 640)
        .onAppear {
            webViewID = UUID()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
