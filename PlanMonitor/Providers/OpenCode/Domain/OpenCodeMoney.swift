import Foundation

/// Money for the OpenCode Console, in `Decimal` dollars.
///
/// The Console API reports amounts as **microcents in decimal strings** — `100,000,000` microcents
/// to the dollar, so `"7525000000"` is $75.25 — and its docs state they are US dollars. `Decimal`
/// keeps every microcent exact, where integer cents would round and `Double` would drift.
///
/// Deliberately not `OpenRouter/Domain/Money.swift` or `ClaudePlatformMoney`: one module is one
/// namespace, and each provider owns its money model. Numbers follow the platform rule — a dot,
/// no thousands separator, at most two decimals, whatever the locale; how the currency is written
/// beside the amount is the user's `CurrencyStyle`.
nonisolated enum OpenCodeMoney {
    /// The docs: "Amounts are in US dollars".
    static let currencyCode = "USD"
    static let microCentsPerDollar = Decimal(100_000_000)

    /// `"7525000000"` → `75.25`. `nil` for `nil`, and for anything that is not a plain decimal
    /// number — `Decimal(string:)` would otherwise read the leading digits of `"12abc"` as 12.
    static func dollars(fromMicroCents string: String?) -> Decimal? {
        guard let string,
              string.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let microCents = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return microCents / microCentsPerDollar
    }

    /// Dropdown form, `1234.50$` with the default style.
    static func format(_ amount: Decimal, style: CurrencyStyle) -> String {
        var number = String(format: "%.2f", (amount as NSDecimalNumber).doubleValue)
        // A sub-cent deficit rounds to zero; it must not print as "-0.00".
        if number == "-0.00" { number = "0.00" }
        return style.apply(to: number, currency: currencyCode)
    }

    /// Menu-bar form, `12$` for 12.50 with the default style.
    static func formatMenuBar(_ amount: Decimal, style: CurrencyStyle) -> String {
        style.apply(to: menuBarNumber(amount), currency: currencyCode)
    }

    /// The menu-bar number without its currency: whole units, and a `k` form from five figures,
    /// both truncated toward zero like every other menu-bar figure — 99,960 is `99.9k`, never a
    /// rounded-up `100.0k`.
    static func menuBarNumber(_ amount: Decimal) -> String {
        let value = (amount as NSDecimalNumber).doubleValue
        if abs(value) >= 10_000 {
            let thousands = value / 1000
            let digits = abs(thousands) >= 100 ? 0 : 1
            let scale = digits == 0 ? 1.0 : 10.0
            let truncated = (thousands * scale).rounded(.towardZero) / scale
            return String(format: "%.\(digits)fk", truncated)
        }
        return "\(Int(value.rounded(.towardZero)))"
    }

    /// Spent against a budget, or `nil` when there is no budget to divide by. Unclamped: spend can
    /// end slightly above a budget, because requests already running are allowed to finish.
    static func usedFraction(spent: Decimal?, budget: Decimal?) -> Double? {
        guard let spent, let budget, budget > 0 else { return nil }
        return (spent as NSDecimalNumber).doubleValue / (budget as NSDecimalNumber).doubleValue
    }
}
