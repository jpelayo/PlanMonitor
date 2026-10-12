import Foundation

/// The text the Claude-API menu-bar item shows, and the used fraction that should tint it.
///
/// In the shape of `Host/MenuBar/MenuBarUsageDigits`: plain numbers in, text out, no colour decided
/// here. It cannot *be* that helper, because that one resolves two percentage windows and this one
/// resolves six money figures against three different denominators.
nonisolated enum ClaudePlatformMenuBarDigits {
    /// The figures the bar can draw, all money in minor units.
    ///
    /// Every field is optional because the console omits what does not apply to an account — a
    /// post-paid org has no prepaid balance, a pre-paid one has nothing to invoice. `nil` means
    /// "not reported", never zero.
    struct Figures: Equatable, Sendable {
        var promoRemaining: Int?
        var promoGranted: Int?
        var spend: Int?
        var spendLimit: Int?
        var prepaidRemaining: Int?
        var invoiced: Int?
        var currency: String

        init(
            promoRemaining: Int? = nil,
            promoGranted: Int? = nil,
            spend: Int? = nil,
            spendLimit: Int? = nil,
            prepaidRemaining: Int? = nil,
            invoiced: Int? = nil,
            currency: String = "USD"
        ) {
            self.promoRemaining = promoRemaining
            self.promoGranted = promoGranted
            self.spend = spend
            self.spendLimit = spendLimit
            self.prepaidRemaining = prepaidRemaining
            self.invoiced = invoiced
            self.currency = currency
        }
    }

    struct Resolved: Equatable, Sendable {
        var text: String?
        /// The *used* fraction of the tightest thing on show, whatever sense the digits display, so
        /// the provider's severity enum has one consistent input. `nil` when nothing on show has a
        /// denominator — a credit balance is not a cap.
        var severityFraction: Double?
    }

    static func resolve(display: ClaudePlatformMenuBarDisplay, figures: Figures) -> Resolved {
        let indicators = display.indicators
        guard !indicators.isEmpty else { return Resolved(text: nil, severityFraction: nil) }

        // An indicator with nothing to report is dropped rather than printed as zero. There is no
        // fallback to a different indicator: unlike the percentage providers' five-hour/weekly pair,
        // these six are not substitutes for one another, and quietly showing spend where the user
        // asked for promotional credit would misreport money.
        let parts = indicators.compactMap { text(for: $0, figures: figures) }
        guard !parts.isEmpty else { return Resolved(text: nil, severityFraction: nil) }

        let fractions = indicators.compactMap { usedFraction(for: $0, figures: figures) }
        return Resolved(
            text: parts.joined(separator: "\u{00B7}"),
            severityFraction: fractions.max()
        )
    }

    private static func text(for indicator: ClaudePlatformIndicator, figures: Figures) -> String? {
        switch indicator {
        case .promoAmount:
            guard let amount = ClaudePlatformMoney.normalizedBalance(figures.promoRemaining) else { return nil }
            return ClaudePlatformMoney.formatMenuBar(minorUnits: amount, currency: figures.currency)

        case .prepaidAmount:
            guard let amount = ClaudePlatformMoney.normalizedBalance(figures.prepaidRemaining) else { return nil }
            return ClaudePlatformMoney.formatMenuBar(minorUnits: amount, currency: figures.currency)

        case .spendAmount:
            guard let amount = figures.spend else { return nil }
            return ClaudePlatformMoney.formatMenuBar(minorUnits: amount, currency: figures.currency)

        case .invoicedAmount:
            guard let amount = figures.invoiced else { return nil }
            return ClaudePlatformMoney.formatMenuBar(minorUnits: amount, currency: figures.currency)

        case .promoPercent:
            // A credit indicator reads as what is left, so this is remaining, not used.
            guard let remaining = figures.promoRemaining, let granted = figures.promoGranted, granted > 0 else { return nil }
            return percent(Double(remaining) / Double(granted))

        case .spendPercent:
            // A spend indicator reads as what has gone.
            guard let fraction = ClaudePlatformMoney.usedFraction(used: figures.spend, limit: figures.spendLimit) else { return nil }
            return percent(fraction)
        }
    }

    /// Always a *used* fraction, so severity means one thing across the six indicators. A bare
    /// balance has no denominator and contributes nothing.
    private static func usedFraction(for indicator: ClaudePlatformIndicator, figures: Figures) -> Double? {
        switch indicator {
        case .promoAmount, .promoPercent:
            guard let remaining = figures.promoRemaining, let granted = figures.promoGranted, granted > 0 else { return nil }
            return Double(granted - remaining) / Double(granted)
        case .spendAmount, .spendPercent:
            return ClaudePlatformMoney.usedFraction(used: figures.spend, limit: figures.spendLimit)
        case .prepaidAmount, .invoicedAmount:
            // Credit purchased over a lifetime is not a ceiling, and an invoice has no cap at all.
            return nil
        }
    }

    /// Truncating, not rounding — the rule every other menu-bar figure in this app follows — and
    /// clamped at zero so an overdrawn balance never prints a negative percentage.
    private static func percent(_ fraction: Double) -> String {
        "\(Int(max(0, fraction * 100)))%"
    }
}
