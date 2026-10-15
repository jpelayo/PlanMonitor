import SwiftUI

struct ProviderControlsRow: View {
    @Bindable var providers: EnabledProviders

    /// Three to a row when one line does not fit the 320pt dropdown — five labels do not, and
    /// Spanish is wider still. Derived from `allCases`, as `ProviderSettingsRow`'s fallback is.
    private static let rows: [[ProviderID]] = stride(from: 0, to: ProviderID.allCases.count, by: 3).map {
        Array(ProviderID.allCases[$0 ..< min($0 + 3, ProviderID.allCases.count)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "Providers"), systemImage: "square.grid.2x2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(ProviderID.allCases) { provider in
                        providerToggle(provider)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func providerToggle(_ provider: ProviderID) -> some View {
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
