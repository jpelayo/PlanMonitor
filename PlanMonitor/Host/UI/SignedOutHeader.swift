import AppKit
import SwiftUI

/// The top of every signed-out dropdown: the provider's menu-bar glyph, a title, one short
/// line, and the primary action. Same geometry for all four; the line wraps instead of
/// truncating.
struct SignedOutHeader: View {
    let symbolName: String
    let fallbackSymbol: String
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void
    /// Optional tap on the glyph (Claude uses it for reviewer mode).
    var onSymbolTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if let onSymbolTap {
                Button(action: onSymbolTap) { symbol }
                    .buttonStyle(.borderless)
            } else {
                symbol
            }
        }
        .accessibilityLabel(title)

        Text(title)
            .font(.headline)

        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)

        Button(actionTitle, action: action)
            .buttonStyle(.borderedProminent)
    }

    private var symbol: some View {
        Image(systemName: resolvedSymbol)
            .font(.system(size: 34, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
    }

    private var resolvedSymbol: String {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil ? symbolName : fallbackSymbol
    }
}
