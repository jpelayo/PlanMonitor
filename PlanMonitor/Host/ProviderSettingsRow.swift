import SwiftUI

struct ProviderSettingsRow: View {
    @Bindable var providers: EnabledProviders

    /// The narrow-width fallback, two to a row. Derived from `allCases` so a new provider can never
    /// be left out of it — the hardcoded 2×2 it replaces would have made a fifth unreachable.
    private static let rows: [[ProviderID]] = stride(from: 0, to: ProviderID.allCases.count, by: 2).map {
        Array(ProviderID.allCases[$0 ..< min($0 + 2, ProviderID.allCases.count)])
    }

    var body: some View {
        ViewThatFits {
            HStack(spacing: 16) { toggles }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Self.rows, id: \.self) { row in
                    GridRow {
                        ForEach(row) { provider in
                            providerToggle(provider)
                        }
                    }
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
