import AppKit
import SwiftUI

/// Grok's one sign-in window: ask x.ai for an approval code, show its page, and wait for the token.
/// The user signs in and approves on that page; the poll finishing is the only success signal.
struct GrokLoginView: View {
    @Bindable var viewModel: GrokUsageViewModel
    @State private var approvalURL: URL?
    @State private var isWorking = false
    @State private var statusText: String?
    @State private var approvalTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Sign in to Grok"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Cancel")) {
                    WindowRouter.shared.close(.loginGrok)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            if let code = viewModel.pendingUserCode {
                // The page shows these letters and a Continue button. Showing the same letters
                // here is what turns a mystery screen into a check.
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

            if let approvalURL {
                GrokLoginWebView(approvalURL: approvalURL)
                    .id(approvalURL)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // One height for all three sign-in windows. Grok needs the room in its own right: the
        // approval page puts its Continue button low, and at the donor's 736 it sat at the very
        // bottom edge — 800 keeps that clear.
        .frame(width: 480, height: 800)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            approvalTask = Task { await connect() }
        }
        .onDisappear {
            // However the window closes: Cancel, the close button, or success.
            approvalTask?.cancel()
            viewModel.cancelDeviceAuthorization()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func connect() async {
        isWorking = true
        statusText = String(localized: "Connecting SuperGrok usage...")
        do {
            approvalURL = try await viewModel.startDeviceAuthorization()
            isWorking = false
            statusText = nil
            try await viewModel.completeDeviceAuthorization()
            WindowRouter.shared.close(.loginGrok)
        } catch is CancellationError {
            // The window was closed; `onDisappear` has already tidied up.
        } catch {
            isWorking = false
            viewModel.cancelDeviceAuthorization()
            statusText = String(localized: "Approval failed. Sign in again.")
        }
    }
}
