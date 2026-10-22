import AppKit
import SwiftUI

struct OpenCodeConnectKeyView: View {
    @Bindable var viewModel: OpenCodeViewModel
    @Environment(\.openURL) private var openURL
    @State private var key = ""

    /// A key's shape, not a sentence: shown as typed, never translated.
    private let placeholder = "oc_sk_…"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect OpenCode").font(.title2.bold())

            Text("PlanMonitor needs an OpenCode Console API key that can **read usage and budgets**. It reads your Go limits, this month's spend and your budget, and cannot call models or spend credit.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open Account → Personal API keys in the OpenCode Console")
                Text("2. Create a key with Restricted permissions: Usage and Budgets set to Read")
                Text("3. Paste it below")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(String(localized: "Open the OpenCode Console")) {
                openURL(URL(string: "https://opencode.ai/console")!)
            }
            .buttonStyle(.link)
            .font(.caption)

            SecureField(placeholder, text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await connect() } }

            if let error = viewModel.connectError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The key is stored in your local Keychain. Requests go directly to OpenCode.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { WindowRouter.shared.close(.connectOpenCode) }
                Button(String(localized: "Connect")) { Task { await connect() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(key.isEmpty || viewModel.isLoading)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func connect() async {
        guard !key.isEmpty else { return }
        if await viewModel.connect(with: key) {
            key = ""
            WindowRouter.shared.close(.connectOpenCode)
        }
    }
}
