import SwiftUI

/// Codex's login view, with one difference: a rejected candidate does **not** reload the page.
/// The web view offers cookies whenever plausible ones appear, which is routinely before sign-in
/// has finished; reloading on every rejection would throw away a half-filled form or a solved
/// challenge. It simply keeps watching until a candidate is a session.
struct ClaudePlatformLoginView: View {
    let onSessionCookiesExtracted: (String) async -> Bool
    @State private var webViewID = UUID()
    @State private var isValidating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Sign in to Claude-API"))
                    .font(.headline)

                Spacer()

                Button(String(localized: "Cancel")) {
                    WindowRouter.shared.close(.loginClaudeAPI)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            // Google refuses sign-in inside an app's web view, so say which path works before the
            // user finds out the hard way.
            Text(String(localized: "Use “Continue with email”. Google sign-in does not work inside this window."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 6)

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

            ClaudePlatformLoginWebView(
                onSessionCookiesExtracted: { cookies in
                    let isSignedIn = await onSessionCookiesExtracted(cookies)
                    if isSignedIn {
                        WindowRouter.shared.close(.loginClaudeAPI)
                    }
                    return isSignedIn
                },
                onValidatingChange: { isValidating = $0 }
            )
            .id(webViewID)
        }
        // The house size since the cookie-banner fix: a banner pinned to the bottom of the web
        // view overlapped the sign-in buttons at 640.
        .frame(width: 480, height: 800)
        .onAppear {
            webViewID = UUID()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
