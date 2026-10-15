import Foundation

/// Money for the Anthropic console, in **integer minor units** with the currency carried alongside.
///
/// Deliberately not `OpenRouter/Domain/Money.swift`: that one is `Decimal` because per-request
/// OpenRouter costs run to fractions of a cent. The console reports whole cents and names its own
/// currency, which is the same shape `ClaudeUsageData` already uses.
///
/// The currency is the one the API reported, or `nil` when it reported none — never an assumed
/// USD. How it is written beside the amount is the user's `CurrencyStyle`.
///
/// Every function takes the payload's own `exponent` (`balance.credits.exponent`, `2` for USD)
/// rather than assuming a hundred minor units to the major one.
nonisolated enum ClaudePlatformMoney {
    /// What the console reports when a balance carries no explicit exponent.
    static let defaultExponent = 2

    /// Below this, a balance is rounding residue rather than money, and reads as zero. Same value
    /// and same reasoning as `ClaudeUsageData.cosmeticPrepaidResidueThresholdMinorUnits`.
    static let residueThresholdMinorUnits = 1

    /// A gauge whose remainder is under this shows empty rather than a sliver.
    static let gaugeDustThresholdMinorUnits = 19

    /// `"199.54$"` with the default style — the dropdown form.
    static func format(minorUnits: Int, currency: String?, exponent: Int = defaultExponent, style: CurrencyStyle) -> String {
        style.apply(to: formatValue(minorUnits: minorUnits, exponent: exponent), currency: currency)
    }

    /// `"199.54"`. Platform rule: a dot whatever the locale, no thousands separator, and never more
    /// than two decimals — a currency with a finer `exponent` is rounded to two for display.
    static func formatValue(minorUnits: Int, exponent: Int = defaultExponent) -> String {
        let digits = min(2, max(0, exponent))
        return String(format: "%.\(digits)f", majorUnits(minorUnits: minorUnits, exponent: exponent))
    }

    /// The compact menu-bar form, `"180$"` with the default style.
    static func formatMenuBar(minorUnits: Int, currency: String?, exponent: Int = defaultExponent, style: CurrencyStyle) -> String {
        style.apply(to: menuBarNumber(minorUnits: minorUnits, exponent: exponent), currency: currency)
    }

    /// The menu-bar number without its currency. Whole units only, because the bar is the one
    /// place where width is scarce, and a `k` form above five figures for the same reason — the
    /// shape `Money.formatMenuBar` settled on.
    ///
    /// Both forms truncate toward zero, like every other menu-bar figure in the app: 99,960 is
    /// `99.9k`, never a rounded-up `100.0k`.
    static func menuBarNumber(minorUnits: Int, exponent: Int = defaultExponent) -> String {
        let whole = majorUnits(minorUnits: minorUnits, exponent: exponent)

        if abs(whole) >= 10_000 {
            let thousands = whole / 1000
            let digits = abs(thousands) >= 100 ? 0 : 1
            let scale = digits == 0 ? 1.0 : 10.0
            let truncated = (thousands * scale).rounded(.towardZero) / scale
            return String(format: "%.\(digits)fk", truncated)
        }

        return "\(Int(whole))"
    }

    /// Minor units as a major-unit amount.
    static func majorUnits(minorUnits: Int, exponent: Int = defaultExponent) -> Double {
        Double(minorUnits) / pow(10, Double(max(0, exponent)))
    }

    /// The used fraction for a gauge, or `nil` when there is no denominator to divide by.
    ///
    /// Unclamped on purpose: overspend is real and the gauges show it by pinning full, which is a
    /// decision for the view, not for this.
    static func usedFraction(used: Int?, limit: Int?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return Double(used) / Double(limit)
    }

    /// A balance normalised for display: negatives clamp to zero, residue reads as zero, and `nil`
    /// stays `nil` — **"not reported" is not the same as "zero"**, and the console returns `null`
    /// for fields that do not apply to an account.
    static func normalizedBalance(_ minorUnits: Int?) -> Int? {
        guard let minorUnits else { return nil }
        let clamped = max(0, minorUnits)
        return clamped <= residueThresholdMinorUnits ? 0 : clamped
    }
}
