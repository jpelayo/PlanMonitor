import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: ClaudeUsageViewModel
    @Bindable var codexViewModel: CodexUsageViewModel
    @Bindable var grokViewModel: GrokUsageViewModel
    @Bindable var openRouterViewModel: OpenRouterBudgetViewModel
    @Bindable var claudeAPIViewModel: ClaudePlatformViewModel
    @Bindable var openCodeViewModel: OpenCodeViewModel
    @Bindable var googleAIViewModel: GoogleAIViewModel
    @Bindable var providers: EnabledProviders
    @Bindable var preferences: GlobalPreferences
    /// Forgets the saved menu bar positions and rebuilds the items at the default spot.
    let resetMenuBarPositions: () -> Void
    /// A tab of the per-provider section: one per enabled provider, plus the grouped dropdown's
    /// own settings while grouping is offered — a tab like a provider, never a section of its own.
    private enum SettingsTab: Hashable {
        case provider(ProviderID)
        case grouped
    }

    @State private var selectedTab: SettingsTab = .provider(.claude)

    private var enabledProviderList: [ProviderID] {
        ProviderID.allCases.filter { providers.isEnabled($0) }
    }

    private var tabs: [SettingsTab] {
        enabledProviderList.map(SettingsTab.provider)
            + (GroupedMenuRule.offersSwitch(enabledCount: providers.values.count) ? [.grouped] : [])
    }

    private func title(for tab: SettingsTab) -> String {
        switch tab {
        case .provider(let provider): provider.displayName
        case .grouped: String(localized: "Grouped menu")
        }
    }

    /// Keeps the selection on a tab that still exists when the set changes underneath it.
    private func repairSelection() {
        if !tabs.contains(selectedTab) {
            selectedTab = tabs.first ?? .provider(.claude)
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

                if GroupedMenuRule.offersSwitch(enabledCount: providers.values.count) {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(String(localized: "Group into one menu-bar item"), isOn: $preferences.groupMenuBarItems)
                            .toggleStyle(.switch)
                        Text(String(localized: "Shows every enabled provider under one icon."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(localized: "Menu bar items"))
                        Spacer()
                        Button(String(localized: "Reset positions"), action: resetMenuBarPositions)
                            .controlSize(.small)
                    }
                    Text(String(localized: "Puts the items back in their default place if a menu bar manager moved them."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            // One section, one provider at a time: the enabled providers are tabs, or a drop-down
            // when the tabs are wider than the row — six were, and the overflow ate the Form's
            // insets. Measured, not counted, so a new provider or a longer name falls back alone.
            Section {
                if tabs.count > 1 {
                    ViewThatFits(in: .horizontal) {
                        providerPicker
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        providerPicker
                            .pickerStyle(.menu)
                    }
                }
                switch selectedTab {
                case .provider(.claude): claudeControls
                case .provider(.codex): codexControls
                case .provider(.grok): grokControls
                case .provider(.openrouter): openRouterControls
                case .provider(.claudeapi): claudePlatformControls
                case .provider(.opencode): openCodeControls
                case .provider(.googleai): googleAIControls
                case .grouped: groupedMenuControls
                }
            } header: {
                Text(tabs.count > 1 ? String(localized: "Providers") : title(for: selectedTab))
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
                    Text(String(localized: "PlanMonitor is an independent tool for use with Claude, Claude Platform, Codex, Google AI, Grok, OpenCode, and OpenRouter. It is not affiliated with the vendors nor endorsed by them."))
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

    /// The "Grouped menu" tab: the provider-name size, the dollar-amount size, and the order of all
    /// six providers (sections and Balances rows), dragged into place.
    @ViewBuilder
    private var groupedMenuControls: some View {
        Picker(String(localized: "Provider name size"), selection: $preferences.groupedTitleSize) {
            ForEach(GroupedTextSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
        .pickerStyle(.menu)

        Picker(String(localized: "Amount size"), selection: $preferences.groupedAmountSize) {
            ForEach(GroupedTextSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
        .pickerStyle(.menu)

        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Order"))
            Text(String(localized: "Drag to reorder."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        // Every provider, enabled or not, so a disabled one keeps its place for when it
        // comes back; disabled ones read secondary.
        ForEach(preferences.groupedOrder) { provider in
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                Text(provider.displayName)
                    .foregroundStyle(providers.isEnabled(provider) ? .primary : .secondary)
            }
        }
        .onMove { source, destination in
            preferences.groupedOrder.move(fromOffsets: source, toOffset: destination)
        }
    }

    private var providerPicker: some View {
        Picker(String(localized: "Provider"), selection: $selectedTab) {
            ForEach(tabs, id: \.self) { tab in
                Text(title(for: tab)).tag(tab)
            }
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
            isRestoring: viewModel.authState == .restoring(email: nil),
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
        VStack(alignment: .leading, spacing: 2) {
            Toggle(String(localized: "Show hidden gauges"), isOn: $codexViewModel.showHiddenGauges)
            Text(String(localized: "Shows limits OpenAI reports outside Codex's own, such as ChatGPT's. What they count is not documented."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        providerAccount(
            email: codexViewModel.authState.email,
            plan: codexViewModel.usageData.planTier.displayName,
            isRestoring: codexViewModel.authState == .restoring(email: nil),
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
            isRestoring: grokViewModel.authState == .restoring,
            signInWindow: .loginGrok,
            signOut: { await grokViewModel.logout() }
        )
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
        } else if case .invalidKey(let reason) = openRouterViewModel.connectionState {
            // The key is still stored: it can be replaced or removed, not "connected" afresh.
            if !reason.isEmpty {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        currencyStylePicker($openRouterViewModel.currencyStyle)
        VStack(alignment: .leading, spacing: 2) {
            Picker(String(localized: "Menu bar ring"), selection: $openRouterViewModel.ringSource) {
                ForEach(OpenRouterRingSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.menu)
            if openRouterViewModel.ringSource == .credit {
                Text(String(localized: "100% is your balance right after the last top-up."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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

    /// The OpenRouter shape — money, its own display and ring pickers, no five-hour/weekly
    /// `MenuBarUsageDisplayControl` or `MenuBarRingControl` — with a session to sign out of, so
    /// the shared account rows rather than OpenRouter's key rows.
    @ViewBuilder
    private var claudePlatformControls: some View {
        SessionTrackingControls(preferences: claudeAPIViewModel.sessionPreferences)
        MenuBarTextControls(preferences: claudeAPIViewModel.menuBarText)
        Picker(String(localized: "Menu bar shows"), selection: $claudeAPIViewModel.menuBarDisplay) {
            ForEach(ClaudePlatformMenuBarDisplay.allCases, id: \.self) { display in
                Text(display.displayName).tag(display)
            }
        }
        .pickerStyle(.menu)
        currencyStylePicker($claudeAPIViewModel.currencyStyle)
        VStack(alignment: .leading, spacing: 2) {
            Picker(String(localized: "Menu bar ring"), selection: $claudeAPIViewModel.ringSource) {
                ForEach(ClaudePlatformRingSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.menu)
            if let caption = claudeAPIViewModel.ringSource.caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        if let organization = claudeAPIViewModel.organizationName {
            LabeledContent(String(localized: "Organization"), value: organization)
        }
        if let recharge = claudeAPIViewModel.snapshot.autoRecharge {
            LabeledContent(
                String(localized: "Auto-payment"),
                value: recharge.isEnabled ? String(localized: "On") : String(localized: "Off")
            )
        }
        providerAccount(
            email: claudeAPIViewModel.authState.email,
            plan: nil,
            isRestoring: claudeAPIViewModel.authState == .restoring(email: nil),
            signInWindow: .loginClaudeAPI,
            signOut: { await claudeAPIViewModel.logout() }
        )
    }

    /// The OpenCode shape is OpenRouter's — a pasted key, its own display and ring pickers — plus a
    /// member picker that only appears when the workspace reports more than one member. Its Go
    /// percentages follow the global "Show percentage" above.
    @ViewBuilder
    private var openCodeControls: some View {
        SessionTrackingControls(preferences: openCodeViewModel.sessionPreferences)
        MenuBarTextControls(preferences: openCodeViewModel.menuBarText)
        if let prefix = openCodeViewModel.connectionState.keyPrefix {
            LabeledContent(String(localized: "Connected with"), value: prefix)
            HStack {
                Button(String(localized: "Replace key")) {
                    WindowRouter.shared.open(.connectOpenCode)
                }
                Button(String(localized: "Remove key"), role: .destructive) {
                    Task { await openCodeViewModel.disconnect() }
                }
            }
        } else {
            Text(String(localized: "Not connected"))
                .foregroundStyle(.secondary)
            Button(String(localized: "Connect OpenCode")) {
                WindowRouter.shared.open(.connectOpenCode)
            }
        }
        if openCodeViewModel.members.count > 1 {
            Picker(String(localized: "Member"), selection: $openCodeViewModel.memberID) {
                Text(String(localized: "Whole workspace")).tag(String?.none)
                ForEach(openCodeViewModel.members) { member in
                    Text(member.email ?? member.userID).tag(Optional(member.userID))
                }
            }
            .pickerStyle(.menu)
        }
        Picker(String(localized: "Menu bar shows"), selection: $openCodeViewModel.menuBarDisplay) {
            ForEach(OpenCodeMenuBarDisplay.allCases, id: \.self) { display in
                Text(display.displayName).tag(display)
            }
        }
        .pickerStyle(.menu)
        if openCodeViewModel.connectionState.showsBudget, !openCodeViewModel.isDemoMode,
           !openCodeViewModel.snapshot.isEmpty, openCodeViewModel.snapshot.go == nil {
            Text(String(localized: "Go limits: not available for this key or workspace."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        currencyStylePicker($openCodeViewModel.currencyStyle)
        VStack(alignment: .leading, spacing: 2) {
            Picker(String(localized: "Menu bar ring"), selection: $openCodeViewModel.ringSource) {
                ForEach(OpenCodeRingSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.menu)
            if let caption = openCodeViewModel.ringSource.caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Google AI has no account to show: agy keeps its own sign-in. What it needs is the helper
    /// script, so that is the row — its state and the ways to install, find and test it. Its
    /// percentage follows the global "Show percentage" above.
    @ViewBuilder
    private var googleAIControls: some View {
        SessionTrackingControls(preferences: googleAIViewModel.sessionPreferences)
        MenuBarTextControls(preferences: googleAIViewModel.menuBarText)
        LabeledContent(String(localized: "Helper script")) {
            switch googleAIViewModel.scriptState {
            case .installed: Text(String(localized: "Installed"))
            case .outdated: Text(String(localized: "Outdated")).foregroundStyle(.orange)
            case .notInstalled: Text(String(localized: "Not installed")).foregroundStyle(.secondary)
            }
        }
        HStack {
            Button(googleAIViewModel.scriptState == .notInstalled
                   ? String(localized: "Install script…")
                   : String(localized: "Reinstall script…")) {
                Task { await googleAIViewModel.installScript() }
            }
            Button(String(localized: "Show folder")) { GoogleAIScriptInstaller.showFolder() }
            Button(String(localized: "Set up…")) { WindowRouter.shared.open(.setupGoogleAI) }
        }
        .onAppear { googleAIViewModel.refreshScriptState() }
    }

    /// The money providers' currency choice — one control, so all read the same.
    private func currencyStylePicker(_ selection: Binding<CurrencyStyle>) -> some View {
        Picker(String(localized: "Currency symbol"), selection: selection) {
            ForEach(CurrencyStyle.allCases, id: \.self) { style in
                Text(style.displayName).tag(style)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func providerAccount(
        email: String?,
        plan: String?,
        isRestoring: Bool,
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
        } else if isRestoring {
            // Still reading the Keychain (or it is locked): signed in, just not confirmed yet.
            // Offering Sign In here would invite a needless second sign-in.
            Text(String(localized: "Checking sign-in…"))
                .foregroundStyle(.secondary)
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
