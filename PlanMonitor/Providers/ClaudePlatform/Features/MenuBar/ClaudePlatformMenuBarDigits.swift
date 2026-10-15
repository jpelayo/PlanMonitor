import Foundation

/// The text the Claude-API menu-bar item shows, and the used fraction that should tint it.
///
/// In the shape of `Host/MenuBar/MenuBarUsageDigits`: plain numbers in, text out, no colour decided
/// here. It cannot *be* that helper, because that one resolves two percentage windows and this one
/// resolves money against two different denominators.
nonisolated enum ClaudePlatformMenuBarDigits {
    /// The three sums the bar can draw from, all money in minor units. `nil` means "not reported",
    /// never zero — a figure that is not there is dropped from the bar, not printed as `$0`.
    struct Figures: Equatable, Sendable {
        /// Every promotional credit granted plus the paid credit on the books.
        var available: Int?
        /// This month's spend.
        var consumed: Int?
        /// The spend limit the account set itself.
        var userLimit: Int?
        /// As reported by the API; `nil` writes amounts bare.
        var currency: String?
        var exponent: Int

        init(
            available: Int? = nil,
            consumed: Int? = nil,
            userLimit: Int? = nil,
            currency: String? = nil,
            exponent: Int = ClaudePlatformMoney.defaultExponent
        ) {
            self.available = available
            self.consumed = consumed
            self.userLimit = userLimit
            self.currency = currency
            self.exponent = exponent
        }

        /// Available minus consumed, never below zero.
        var left: Int? {
            guard let available, let consumed else { return nil }
            return max(0, available - consumed)
        }

        /// The account's own limit minus consumed, never below zero.
        var leftUnderUserLimit: Int? {
            guard let userLimit, let consumed else { return nil }
            return max(0, userLimit - consumed)
        }
    }

    struct Resolved: Equatable, Sendable {
        var text: String?
        /// The *used* fraction behind what is on show, so the provider's severity enum has one
        /// consistent input whatever sense the digits read in. `nil` when there is no denominator.
        var severityFraction: Double?
    }

    static func resolve(display: ClaudePlatformMenuBarDisplay, figures: Figures, style: CurrencyStyle) -> Resolved {
        let usedOfAvailable = ClaudePlatformMoney.usedFraction(used: figures.consumed, limit: figures.available)
        // Only the account's own limit: Anthropic's cap is not "the maximum set by the user", so
        // with no own limit the three limit choices have nothing to show.
        let usedOfUserLimit = ClaudePlatformMoney.usedFraction(used: figures.consumed, limit: figures.userLimit)

        switch display {
        case .iconOnly:
            return Resolved(text: nil, severityFraction: nil)

        case .consumed:
            guard let consumed = figures.consumed else { return .nothing }
            return Resolved(text: money(consumed, figures, style), severityFraction: usedOfAvailable)

        case .left:
            guard let left = figures.left else { return .nothing }
            return Resolved(text: money(left, figures, style), severityFraction: usedOfAvailable)

        case .consumedOfAvailable:
            guard let consumed = figures.consumed, let available = figures.available, usedOfAvailable != nil else { return .nothing }
            return Resolved(text: pair(consumed, available, figures, style), severityFraction: usedOfAvailable)

        case .leftOfAvailable:
            guard let left = figures.left, let available = figures.available, usedOfAvailable != nil else { return .nothing }
            return Resolved(text: pair(left, available, figures, style), severityFraction: usedOfAvailable)

        case .consumedOfUserLimit:
            guard let consumed = figures.consumed, let limit = figures.userLimit, usedOfUserLimit != nil else { return .nothing }
            return Resolved(text: pair(consumed, limit, figures, style), severityFraction: usedOfUserLimit)

        case .leftUnderUserLimit:
            guard let left = figures.leftUnderUserLimit else { return .nothing }
            return Resolved(text: money(left, figures, style), severityFraction: usedOfUserLimit)

        case .leftOfUserLimit:
            guard let left = figures.leftUnderUserLimit, let limit = figures.userLimit, usedOfUserLimit != nil else { return .nothing }
            return Resolved(text: pair(left, limit, figures, style), severityFraction: usedOfUserLimit)
        }
    }

    /// Whole units, truncated — the rule every other menu-bar figure in this app follows.
    private static func money(_ amount: Int, _ figures: Figures, _ style: CurrencyStyle) -> String {
        ClaudePlatformMoney.formatMenuBar(minorUnits: amount, currency: figures.currency, exponent: figures.exponent, style: style)
    }

    /// Two amounts with `/` between them and the currency written once for both, `19/200$`
    /// (`USD 19/200` with the code before): the bar has no width for it twice. Never a percentage.
    private static func pair(_ first: Int, _ second: Int, _ figures: Figures, _ style: CurrencyStyle) -> String {
        let numbers = ClaudePlatformMoney.menuBarNumber(minorUnits: first, exponent: figures.exponent)
            + "/" + ClaudePlatformMoney.menuBarNumber(minorUnits: second, exponent: figures.exponent)
        return style.apply(to: numbers, currency: figures.currency)
    }
}

private extension ClaudePlatformMenuBarDigits.Resolved {
    static let nothing = Self(text: nil, severityFraction: nil)
}
