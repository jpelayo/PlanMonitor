import Foundation

/// OpenRouter's API names no currency anywhere; its credits are USD, so that is the code used
/// (user decision, 2026-10-14). Numbers follow the platform rule — a dot, no thousands separator,
/// at most two decimals, whatever the locale; how the currency is written beside the amount is
/// the user's `CurrencyStyle`.
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

    /// Dropdown form: two decimals, e.g. `1234.54$`. Platform rule: a dot, never the locale's
    /// separator, and no thousands separator.
    static func format(_ amount: Decimal, style: CurrencyStyle) -> String {
        var number = String(format: "%.2f", (displayValue(amount) as NSDecimalNumber).doubleValue)
        // A sub-cent deficit rounds to zero; it must not print as "-0.00".
        if number == "-0.00" { number = "0.00" }
        return style.apply(to: number, currency: currencyCode)
    }

    /// Menu-bar form: whole units, e.g. `25$` for 25.54, with no thousands separator.
    ///
    /// The value is **floored**, not rounded: 25.54 shows as 25, never 26, so the figure
    /// never overstates what is available. Flooring is uniformly conservative, so a
    /// deficit of -3.40 reads -4 rather than flattering to -3.
    static func formatMenuBar(_ amount: Decimal, style: CurrencyStyle) -> String {
        let value = displayValue(amount)

        // Above five figures, whole units get wide; fall back to a k form.
        if abs(value) >= 10_000 {
            let thousands = value / 1000
            let rounded = (thousands as NSDecimalNumber).doubleValue
            let digits = abs(rounded) >= 100 ? 0 : 1
            return style.apply(to: String(format: "%.\(digits)fk", rounded), currency: currencyCode)
        }

        let floored = floor(value)
        return style.apply(to: "\((floored as NSDecimalNumber).intValue)", currency: currencyCode)
    }

    /// Floors toward negative infinity, so the displayed figure never claims more
    /// credit than exists.
    private static func floor(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .down)
        return result
    }


    /// `spent / limit`, unclamped so overspend can render as > 100%.
    /// Returns nil when the limit is zero or negative, where a fraction is meaningless.
    static func fraction(spent: Decimal, limit: Decimal) -> Double? {
        guard limit > 0 else { return nil }
        return NSDecimalNumber(decimal: spent).doubleValue
            / NSDecimalNumber(decimal: limit).doubleValue
    }
}
