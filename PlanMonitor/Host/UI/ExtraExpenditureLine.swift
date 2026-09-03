import SwiftUI

/// The "Extra expenditure: Enabled (13.59 USD / 50.00 USD)" header line, extracted from the
/// Claude menu so Codex and Grok render it with the same rules:
/// - hidden when the provider says nothing about extra spend (`enabled == nil`);
/// - bold/primary when enabled, regular/secondary when disabled;
/// - amounts only once spend has actually started.
struct ExtraExpenditureLine: View {
    let enabled: Bool?
    let hasStartedSpend: Bool
    let usedFormatted: String?
    let limitFormatted: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.caption2.weight(enabled == true ? .semibold : .regular))
                .foregroundStyle(enabled == true ? .primary : .secondary)
        }
    }

    var text: String? {
        Self.text(
            enabled: enabled,
            hasStartedSpend: hasStartedSpend,
            usedFormatted: usedFormatted,
            limitFormatted: limitFormatted
        )
    }

    static func text(
        enabled: Bool?,
        hasStartedSpend: Bool,
        usedFormatted: String?,
        limitFormatted: String?
    ) -> String? {
        guard let enabled else { return nil }
        let status = String(localized: enabled ? "Enabled" : "Disabled")
        let title = String(localized: "Extra expenditure")
        if hasStartedSpend, let usedFormatted, let limitFormatted {
            return "\(title): \(status) (\(usedFormatted) / \(limitFormatted))"
        }
        return "\(title): \(status)"
    }
}
