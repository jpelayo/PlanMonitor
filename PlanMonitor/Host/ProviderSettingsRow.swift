import SwiftUI

struct ProviderSettingsRow: View {
    @Bindable var providers: EnabledProviders

    var body: some View {
        ViewThatFits {
            HStack(spacing: 16) { toggles }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    providerToggle(.claude)
                    providerToggle(.codex)
                }
                GridRow {
                    providerToggle(.grok)
                    providerToggle(.openrouter)
                }
            }
        }
    }

    @ViewBuilder
    private var toggles: some View {
        ForEach(ProviderID.allCases) { provider in
            providerToggle(provider)
        }
    }

    private func providerToggle(_ provider: ProviderID) -> some View {
        Toggle(provider.displayName, isOn: providers.binding(for: provider))
            .toggleStyle(.checkbox)
            .disabled(providers.isEnabled(provider) && !providers.canDisable(provider))
    }
}
