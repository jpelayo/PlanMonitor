import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: ClaudeUsageViewModel
    @Bindable var codexViewModel: CodexUsageViewModel
    @Bindable var grokViewModel: GrokUsageViewModel
    @Bindable var openRouterViewModel: OpenRouterBudgetViewModel
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences
    @State private var selectedProvider: ProviderID = .claude

    private var enabledProviderList: [ProviderID] {
        ProviderID.allCases.filter { providers.isEnabled($0) }
    }

    /// Keeps the tab on an enabled provider when the set changes underneath it.
    private func repairSelection() {
        if !providers.isEnabled(selectedProvider) {
            selectedProvider = enabledProviderList.first ?? .claude
        }
    }

    var body: some View {
        Form {
            Section(String(localized: "Providers")) {
                ProviderSettingsRow(providers: providers)
                Text(String(localized: "At least one provider must remain enabled."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "General")) {
                Toggle(String(localized: "Launch at login"), isOn: $preferences.launchAtLogin)
                if let notice = preferences.launchAtLoginNotice {
                    HStack(alignment: .firstTextBaseline) {
                        Text(notice)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(String(localized: "Open Login Items…")) {
                            LoginItemController.openSystemSettings()
                        }
                        .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Picker(String(localized: "Change language"), selection: $preferences.appLanguage) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(String(localized: "(requires app restart)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "Display")) {
                Picker(String(localized: "Show percentage"), selection: $preferences.showRemainingPercent) {
                    Text(String(localized: "Remaining")).tag(true)
                    Text(String(localized: "Used")).tag(false)
                }
                .pickerStyle(.menu)

                Picker(String(localized: "Update interval"), selection: $preferences.pollingIntervalMinutes) {
                    ForEach(GlobalPreferences.supportedPollingIntervals, id: \.self) { minutes in
                        Text(String(localized: "\(minutes) minutes")).tag(minutes)
                    }
                }
                .pickerStyle(.menu)

                Text(String(localized: "Dropdown gauges always show used percentage. Each provider chooses what its own menu bar item shows."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // One section, one provider at a time: the enabled providers are tabs.
            Section {
                if enabledProviderList.count > 1 {
                    Picker(selection: $selectedProvider) {
                        ForEach(enabledProviderList) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                switch selectedProvider {
                case .claude: claudeControls
                case .codex: codexControls
                case .grok: grokControls
                case .openrouter: openRouterControls
                }
            } header: {
                Text(enabledProviderList.count > 1 ? String(localized: "Providers") : selectedProvider.displayName)
            }
            .onAppear { repairSelection() }
            .onChange(of: providers.values) { _, _ in repairSelection() }

            Section {
                LabeledContent(String(localized: "Version"), value: Bundle.main.comboAppVersion)
                LabeledContent(String(localized: "Developer")) {
                    Link("infinitecontext.com", destination: URL(string: "https://infinitecontext.com")!)
                }
                LabeledContent(String(localized: "Source code")) {
                    Link(destination: URL(string: "https://github.com/jpelayo/PlanMonitor")!) {
                        Text(verbatim: "github.com/jpelayo/PlanMonitor")
                    }
                }
                LabeledContent(String(localized: "About")) {
                    Text(String(localized: "PlanMonitor is an independent tool for use with Claude, Codex, Grok, and OpenRouter. It is not affiliated with the vendors nor endorsed by them."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            preferences.refreshLoginItemState()
        }
    }

    @ViewBuilder
    private var claudeControls: some View {
        SessionTrackingControls(preferences: viewModel.sessionPreferences)
        MenuBarRingControl(preferences: viewModel.menuBarText)
        MenuBarUsageDisplayControl(preferences: viewModel.menuBarText)
        MenuBarTextControls(preferences: viewModel.menuBarText)
        providerAccount(
            email: viewModel.authState.email,
            plan: viewModel.usageData.planDisplayName,
            signInWindow: .loginClaude,
            signOut: { await viewModel.logout() }
        )
    }

    @ViewBuilder
    private var codexControls: some View {
        SessionTrackingControls(preferences: codexViewModel.sessionPreferences)
        MenuBarRingControl(preferences: codexViewModel.menuBarText)
        MenuBarUsageDisplayControl(preferences: codexViewModel.menuBarText)
        MenuBarTextControls(preferences: codexViewModel.menuBarText)
        providerAccount(
            email: codexViewModel.authState.email,
            plan: codexViewModel.usageData.planTier.displayName,
            signInWindow: .loginCodex,
            signOut: { await codexViewModel.logout() }
        )
    }

    @ViewBuilder
    private var grokControls: some View {
        SessionTrackingControls(preferences: grokViewModel.sessionPreferences)
        MenuBarRingControl(preferences: grokViewModel.menuBarText)
        MenuBarUsageDisplayControl(preferences: grokViewModel.menuBarText)
        MenuBarTextControls(preferences: grokViewModel.menuBarText)
        providerAccount(
            email: grokViewModel.authState.email,
            plan: grokViewModel.usageData.planDisplayName,
            signInWindow: .loginGrok,
            signOut: { await grokViewModel.logout() }
        )
        if grokViewModel.needsUsageAuthorization {
            Text(String(localized: "Usage access still needs approval. Open the sign-in window to finish."))
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var openRouterControls: some View {
        SessionTrackingControls(preferences: openRouterViewModel.sessionPreferences)
        MenuBarTextControls(preferences: openRouterViewModel.menuBarText)
        if let identity = openRouterViewModel.connectionState.identity {
            LabeledContent(String(localized: "Connected as"), value: identity.label)
            HStack {
                Button(String(localized: "Replace key")) {
                    WindowRouter.shared.open(.connectOpenRouter)
                }
                Button(String(localized: "Remove management key"), role: .destructive) {
                    Task { await openRouterViewModel.disconnect() }
                }
            }
        } else {
            Text(String(localized: "Not connected"))
                .foregroundStyle(.secondary)
            Button(String(localized: "Connect OpenRouter")) {
                WindowRouter.shared.open(.connectOpenRouter)
            }
        }
        Picker(String(localized: "Menu bar shows"), selection: $openRouterViewModel.menuBarDisplay) {
            ForEach(MenuBarDisplay.allCases, id: \.self) { display in
                Text(display.displayName).tag(display)
            }
        }
        .pickerStyle(.menu)
        Toggle(String(localized: "Show disabled keys"), isOn: $openRouterViewModel.showDisabledKeys)
        Toggle(String(localized: "Show recent models"), isOn: $openRouterViewModel.showRecentModels)
        if openRouterViewModel.showRecentModels {
            Picker(String(localized: "Recent models window"), selection: $openRouterViewModel.recentModelsWindow) {
                ForEach(RecentModelsWindow.allCases, id: \.self) { window in
                    Text(window.displayName).tag(window)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func providerAccount(
        email: String?,
        plan: String?,
        signInWindow: WindowRouter.AppWindow,
        signOut: @escaping @MainActor () async -> Void
    ) -> some View {
        if let email {
            LabeledContent(String(localized: "Signed in as"), value: email)
            if let plan, !plan.isEmpty {
                LabeledContent(String(localized: "Plan"), value: plan)
            }
            Button(String(localized: "Sign Out"), role: .destructive) {
                Task { await signOut() }
            }
        } else {
            Text(String(localized: "Not signed in"))
                .foregroundStyle(.secondary)
            Button(String(localized: "Sign In")) {
                WindowRouter.shared.open(signInWindow)
            }
        }
    }

}

private extension Bundle {
    var comboAppVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
