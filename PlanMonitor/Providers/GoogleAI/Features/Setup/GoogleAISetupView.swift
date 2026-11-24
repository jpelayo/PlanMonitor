import AppKit
import SwiftUI

/// "Set up Google AI": why a script, the three steps, the script itself, and the buttons that
/// install, locate and test it. `OpenCodeConnectKeyView`'s shape.
struct GoogleAISetupView: View {
    @Bindable var viewModel: GoogleAIViewModel
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up Google AI").font(.title2.bold())

            Text("PlanMonitor reads your Antigravity limits with the **agy** command. macOS does not let it run other programs itself, but it can run a script you install in its scripts folder.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Install the Antigravity CLI: brew install --cask antigravity-cli")
                Text("2. Run agy once in Terminal and sign in")
                Text("3. Click Install script and save it in the folder that opens")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            ScrollView {
                Text(verbatim: GoogleAIScript.contents)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 150)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Text(String(localized: "Helper script"))
                Spacer()
                Text(scriptStateText)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if let message = viewModel.setupMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(viewModel.lastError == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("The script only runs agy -p /usage. PlanMonitor stores no Google credentials.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button(String(localized: "Show folder")) { GoogleAIScriptInstaller.showFolder() }
                Spacer()
                Button(String(localized: "Test now")) {
                    Task { isWorking = true; await viewModel.testNow(); isWorking = false }
                }
                .disabled(viewModel.scriptState == .notInstalled || isWorking)
                Button(installTitle) {
                    Task { isWorking = true; await viewModel.installScript(); isWorking = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            viewModel.refreshScriptState()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var installTitle: String {
        viewModel.scriptState == .notInstalled
            ? String(localized: "Install script…")
            : String(localized: "Reinstall script…")
    }

    private var scriptStateText: String {
        switch viewModel.scriptState {
        case .installed: String(localized: "Installed")
        case .outdated: String(localized: "Outdated")
        case .notInstalled: String(localized: "Not installed")
        }
    }
}
