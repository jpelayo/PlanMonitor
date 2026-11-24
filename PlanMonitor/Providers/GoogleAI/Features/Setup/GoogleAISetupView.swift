import AppKit
import SwiftUI

/// "Set up Google AI": one sentence, the result line, and two buttons — Test now and Install.
/// No script text, steps or folders (user request, 2026-11-24): Install opens the Save dialog
/// already in the right folder and tests right after; the result line says what's missing, if
/// anything. The script itself stays in `GoogleAIScript.contents`; "Show folder" lives in Settings.
struct GoogleAISetupView: View {
    @Bindable var viewModel: GoogleAIViewModel
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up Google AI").font(.title2.bold())

            Text("PlanMonitor reads your Antigravity limits through the Antigravity command-line tool. Install adds a small helper so it can.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.setupMessage ?? scriptStateText)
                .font(.caption)
                .foregroundStyle(viewModel.setupMessage != nil && viewModel.lastError != nil ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
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
        .frame(width: 420)
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
