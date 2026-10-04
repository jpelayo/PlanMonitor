//
//  ClaudeLoginView.swift
//  PlanTracker
//

import SwiftUI

struct ClaudeLoginView: View {
    let onSessionKeyExtracted: (String) -> Void
    @State private var webViewID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Sign in to Claude"))
                    .font(.headline)

                Spacer()

                Button(String(localized: "Cancel")) {
                    WindowRouter.shared.close(.loginClaude)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            ClaudeLoginWebView(onSessionKeyExtracted: { sessionKey in
                onSessionKeyExtracted(sessionKey)
                WindowRouter.shared.close(.loginClaude)
            })
            .id(webViewID)
        }
        // Taller than the page needs, and the same height for all three providers: a cookie
        // banner pinned to the bottom of the web view overlapped the sign-in buttons at 640.
        .frame(width: 480, height: 800)
        .onAppear {
            webViewID = UUID()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
