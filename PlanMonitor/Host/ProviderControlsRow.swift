import SwiftUI

struct ProviderControlsRow: View {
    @Bindable var providers: EnabledProviders

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "Providers"), systemImage: "square.grid.2x2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(ProviderID.allCases) { provider in
                    Toggle(provider.displayName, isOn: providers.binding(for: provider))
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption2)
                        .disabled(
                            providers.isEnabled(provider)
                                && !providers.canDisable(provider)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
