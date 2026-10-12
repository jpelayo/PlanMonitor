import Foundation

/// Money for the Anthropic console, in **integer minor units** with the currency carried alongside.
///
/// Deliberately not `OpenRouter/Domain/Money.swift`: that one is `Decimal` because per-request
/// OpenRouter costs run to fractions of a cent, and it hardcodes `"USD"` plus a `"$"` symbol. The
/// console reports whole cents and names its own currency per bucket, which is the same shape
/// `ClaudeUsageData` already uses — so the formatting below is Claude's, not OpenRouter's.
nonisolated enum ClaudePlatformMoney {
    /// Below this, a balance is rounding residue rather than money, and reads as zero. Same value
    /// and same reasoning as `ClaudeUsageData.cosmeticPrepaidResidueThresholdMinorUnits`.
    static let residueThresholdMinorUnits = 1

    /// A gauge whose remainder is under this shows empty rather than a sliver.
    static let gaugeDustThresholdMinorUnits = 19

    /// `"199.54 USD"` — the dropdown form, matching `ClaudeUsageData.formatCurrency`.
    static func format(minorUnits: Int, currency: String) -> String {
        "\(formatValue(minorUnits: minorUnits)) \(currency)"
    }

    /// `"199.54"` — locale-blind on purpose, so it lines up with the rest of the app.
    static func formatValue(minorUnits: Int) -> String {
        String(format: "%.2f", Double(minorUnits) / 100.0)
    }

    /// The compact menu-bar form. Whole units only, because the bar is the one place where width is
    /// scarce, and a `k` form above five figures for the same reason — the shape
    /// `Money.formatMenuBar` settled on. USD gets the bare `$`; anything else keeps its code, since
    /// a symbol table for every currency the console might name is not worth carrying.
    static func formatMenuBar(minorUnits: Int, currency: String) -> String {
        let whole = Double(minorUnits) / 100.0
        let isUSD = currency.uppercased() == "USD"

        if abs(whole) >= 10_000 {
            let thousands = whole / 1000
            let digits = abs(thousands) >= 100 ? 0 : 1
            let number = String(format: "%.\(digits)fk", thousands)
            return isUSD ? "$\(number)" : "\(number) \(currency)"
        }

        // Truncating toward zero, like every other menu-bar figure in the app.
        let truncated = Int(whole)
        return isUSD ? "$\(truncated)" : "\(truncated) \(currency)"
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
