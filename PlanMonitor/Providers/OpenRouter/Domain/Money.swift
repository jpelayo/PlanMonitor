import Foundation

/// OpenRouter credits are USD-denominated regardless of the viewer's locale, so the
/// currency code is fixed while separators and symbol placement follow the locale.
///
/// Money is `Decimal` throughout, never `Double`. Per-request costs run to small
/// fractions of a cent (`0.015`), which integer minor units would round to zero.
nonisolated enum Money {
    static let currencyCode = "USD"

    /// Anything below half a cent is cosmetic residue from provider-side rounding.
    /// Snap it to zero for display only — never for arithmetic, and never for a
    /// genuinely negative balance, which the user needs to see.
    static let residueThreshold = Decimal(string: "0.005")!

    static func displayValue(_ amount: Decimal) -> Decimal {
        guard amount > 0, amount < residueThreshold else { return amount }
        return 0
    }

    static func format(_ amount: Decimal) -> String {
        displayValue(amount).formatted(.currency(code: currencyCode))
    }

    /// Menu-bar form: whole units and a bare `$`, e.g. `25$` for 25.54.
    ///
    /// Two deliberate choices. The symbol is forced to `$` rather than the locale's
    /// disambiguated form — a Spanish locale renders USD as `US$`, which costs three
    /// characters of menu-bar width to say something the user already knows. And the
    /// value is **floored**, not rounded: 25.54 shows as 25, never 26, so the figure
    /// never overstates what is available. Flooring is uniformly conservative, so a
    /// deficit of -3.40 reads -4$ rather than flattering to -3$.
    ///
    /// Symbol placement and grouping still follow the locale, so this is `25$` in
    /// Spanish and `$25` in English.
    static func formatMenuBar(_ amount: Decimal) -> String {
        let value = displayValue(amount)

        // Above five figures, whole units get wide; fall back to a k form.
        if abs(value) >= 10_000 {
            let thousands = value / 1000
            let rounded = (thousands as NSDecimalNumber).doubleValue
            let digits = abs(rounded) >= 100 ? 0 : 1
            let number = String(format: "%.\(digits)fk", rounded)
            return stripSpaces(placeSymbol(number))
        }

        let floored = floor(value)
        let formatted = menuBarFormatter.string(from: floored as NSDecimalNumber)
            ?? placeSymbol("\((floored as NSDecimalNumber).intValue)")
        return stripSpaces(formatted)
    }

    /// Floors toward negative infinity, so the displayed figure never claims more
    /// credit than exists.
    private static func floor(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .down)
        return result
    }

    private static let menuBarFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// Spanish renders USD as `25 $` with a non-breaking space. In the menu bar that
    /// gap buys nothing and costs width, so it goes: `25$`.
    private static func stripSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Mirrors the locale's currency placement for a pre-rendered number string.
    private static func placeSymbol(_ number: String) -> String {
        let sample = menuBarFormatter.string(from: 1) ?? "$1"
        return sample.hasPrefix("$") ? "$\(number)" : "\(number)$"
    }

    /// `spent / limit`, unclamped so overspend can render as > 100%.
    /// Returns nil when the limit is zero or negative, where a fraction is meaningless.
    static func fraction(spent: Decimal, limit: Decimal) -> Double? {
        guard limit > 0 else { return nil }
        return NSDecimalNumber(decimal: spent).doubleValue
            / NSDecimalNumber(decimal: limit).doubleValue
    }
}
