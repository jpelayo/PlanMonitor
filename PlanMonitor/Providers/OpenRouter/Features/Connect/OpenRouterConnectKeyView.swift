import AppKit
import SwiftUI

struct OpenRouterConnectKeyView: View {
    @Bindable var viewModel: OpenRouterBudgetViewModel
        @Environment(\.openURL) private var openURL
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect OpenRouter").font(.title2.bold())

            Text("PlanMonitor needs a **management key**. It reads your credit balance, key limits, and guardrails — and cannot make model calls or spend credit.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Open Settings → Management Keys at openrouter.ai")
                Text("2. Click Create New Key")
                Text("3. Paste it below")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(String(localized: "Open OpenRouter management keys")) {
                openURL(URL(string: "https://openrouter.ai/settings/management-keys")!)
            }
            .buttonStyle(.link)
            .font(.caption)

            SecureField(String(localized: "sk-or-v1-…"), text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await connect() } }

            if let error = viewModel.connectError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The key is stored in your local Keychain. Requests go directly to OpenRouter.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { WindowRouter.shared.close(.connectOpenRouter) }
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
            WindowRouter.shared.close(.connectOpenRouter)
        }
    }
}
