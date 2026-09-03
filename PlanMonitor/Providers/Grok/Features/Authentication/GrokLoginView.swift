import AppKit
import SwiftUI

struct GrokLoginView: View {
    @Bindable var viewModel: GrokUsageViewModel
    @State private var webViewID = UUID()
    @State private var isWorking = false
    @State private var statusText: String?
    @State private var followUpURL: URL?
    @State private var seedCookies: String?
    @State private var isReady = false
    @State private var didStartUsageAuthorization = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Sign in to Grok"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Cancel")) {
                    NSApp.setActivationPolicy(.accessory)
                    WindowRouter.shared.close(.loginGrok)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            if let code = viewModel.pendingUserCode {
                // Step 4: the page shows these letters and a Continue button. Showing the
                // same letters here is what turns a mystery screen into a check.
                VStack(spacing: 4) {
                    Text(code)
                        .font(.title2.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                    Text(String(localized: "Confirm letters match and press Continue"))
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.tint.opacity(0.12))
            } else if let statusText {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if isReady {
                GrokLoginWebView(
                    followUpURL: followUpURL,
                    seedCookies: seedCookies,
                    onSessionCookiesExtracted: { sessionCookies in
                        Task { await handleExtractedCookies(sessionCookies) }
                    }
                )
                .id(webViewID)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Taller than the donor's 736: the approval page puts its Continue button low, and
        // at the old height it sat at the very bottom edge.
        .frame(width: 480, height: 846)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            Task { await prepare() }
        }
    }

    private func prepare() async {
        seedCookies = await viewModel.storedCookies()
        isReady = true
        if seedCookies != nil {
            await connectUsage()
        }
    }

    private func handleExtractedCookies(_ sessionCookies: String) async {
        guard !didStartUsageAuthorization else { return }
        isWorking = true
        statusText = String(localized: "Validating session...")
        let isAuthenticated = await viewModel.handleLoginSuccess(sessionCookies: sessionCookies)
        guard isAuthenticated else {
            isWorking = false
            statusText = String(localized: "Sign-in failed. Try again.")
            followUpURL = nil
            seedCookies = nil
            webViewID = UUID()
            return
        }
        seedCookies = sessionCookies
        await connectUsage()
    }

    private func connectUsage() async {
        guard !didStartUsageAuthorization else { return }
        didStartUsageAuthorization = true
        isWorking = true
        statusText = String(localized: "Connecting SuperGrok usage...")
        do {
            let url = try await viewModel.startDeviceAuthorization()
            statusText = String(localized: "Approve SuperGrok usage access…")
            followUpURL = url
            try await viewModel.completeDeviceAuthorization()
            isWorking = false
            NSApp.setActivationPolicy(.accessory)
            WindowRouter.shared.close(.loginGrok)
        } catch {
            didStartUsageAuthorization = false
            isWorking = false
            statusText = String(localized: "Approval failed. Sign in again.")
        }
    }
}
