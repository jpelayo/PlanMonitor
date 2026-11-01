import Foundation

/// The text the Claude-API menu-bar item shows, and the used fraction that should tint it.
///
/// In the shape of `Host/MenuBar/MenuBarUsageDigits`: plain numbers in, text out, no colour decided
/// here. It cannot *be* that helper, because that one resolves two percentage windows and this one
/// resolves money against different denominators.
nonisolated enum ClaudePlatformMenuBarDigits {
    /// The balances and counters the bar draws from, all money in minor units. `nil` means "not
    /// reported", never zero — a figure that is not there is dropped from the bar, not printed as `$0`.
    ///
    /// Credit is read from the balances themselves, never as a grant minus this month's spend: the
    /// balances already count every month's use, while the spend counter resets on the 1st. Mixing
    /// the two read 199$ on 2026-11-01 for an account holding 31.87$ (user report).
    struct Figures: Equatable, Sendable {
        /// Promotional credit as granted, and what is left of it, over the live tranches.
        var promoGranted: Int?
        var promoLeft: Int?
        /// Card-paid credit on the books. The console reports its balance, never what was bought.
        var prepaidLeft: Int?
        /// This month's spend.
        var spent: Int?
        /// The spend limit the account set itself.
        var userLimit: Int?
        /// Post-paid usage not yet invoiced — reported only by an invoiced account.
        var pendingInvoice: Int?
        /// A pre-paid account that is not topped up automatically: requests stop when the credit
        /// runs out, so what is left to spend can never exceed the credit left.
        var spendingStopsAtCredit: Bool
        /// As reported by the API; `nil` writes amounts bare.
        var currency: String?
        var exponent: Int

        init(
            promoGranted: Int? = nil,
            promoLeft: Int? = nil,
            prepaidLeft: Int? = nil,
            spent: Int? = nil,
            userLimit: Int? = nil,
            pendingInvoice: Int? = nil,
            spendingStopsAtCredit: Bool = false,
            currency: String? = nil,
            exponent: Int = ClaudePlatformMoney.defaultExponent
        ) {
            self.promoGranted = promoGranted
            self.promoLeft = promoLeft
            self.prepaidLeft = prepaidLeft
            self.spent = spent
            self.userLimit = userLimit
            self.pendingInvoice = pendingInvoice
            self.spendingStopsAtCredit = spendingStopsAtCredit
            self.currency = currency
            self.exponent = exponent
        }

        /// The credit the account holds now: promotional plus prepaid (user decision, 2026-11-01).
        var creditLeft: Int? {
            guard promoLeft != nil || prepaidLeft != nil else { return nil }
            return (promoLeft ?? 0) + (prepaidLeft ?? 0)
        }

        /// Promotional credit as granted plus the prepaid balance, the only prepaid figure there is.
        var creditTotal: Int? {
            guard promoGranted != nil || prepaidLeft != nil else { return nil }
            return (promoGranted ?? 0) + (prepaidLeft ?? 0)
        }

        /// Credit total minus credit left, never below zero.
        var creditUsed: Int? {
            guard let creditTotal, let creditLeft else { return nil }
            return max(0, creditTotal - creditLeft)
        }

        var promoUsed: Int? {
            guard let promoGranted, let promoLeft else { return nil }
            return max(0, promoGranted - promoLeft)
        }

        /// The account's own limit minus this month's spend, never below zero — and never more
        /// than the credit left when spending stops there (user decision, 2026-11-01).
        var leftToSpend: Int? {
            guard let userLimit, let spent else { return nil }
            let room = max(0, userLimit - spent)
            if spendingStopsAtCredit, let creditLeft {
                return min(room, creditLeft)
            }
            return room
        }
    }

    struct Resolved: Equatable, Sendable {
        var text: String?
        /// The *used* fraction behind what is on show, so the provider's severity enum has one
        /// consistent input whatever sense the digits read in. `nil` when there is no denominator.
        var severityFraction: Double?
    }

    static func resolve(display: ClaudePlatformMenuBarDisplay, figures: Figures, style: CurrencyStyle) -> Resolved {
        let creditUsedShare = ClaudePlatformMoney.usedFraction(used: figures.creditUsed, limit: figures.creditTotal)
        let promoUsedShare = ClaudePlatformMoney.usedFraction(used: figures.promoUsed, limit: figures.promoGranted)
        // Only the account's own limit: Anthropic's cap is not "the maximum set by the user", so
        // with no own limit the limit choices have nothing to show.
        let spentShare = ClaudePlatformMoney.usedFraction(used: figures.spent, limit: figures.userLimit)
        let leftToSpendShare = ClaudePlatformMoney.usedFraction(
            used: figures.userLimit.flatMap { limit in figures.leftToSpend.map { limit - $0 } },
            limit: figures.userLimit
        )

        switch display {
        case .iconOnly:
            return Resolved(text: nil, severityFraction: nil)

        case .left:
            guard let left = figures.creditLeft else { return .nothing }
            return Resolved(text: money(left, figures, style), severityFraction: creditUsedShare)

        case .leftOfAvailable:
            guard let left = figures.creditLeft, let total = figures.creditTotal, creditUsedShare != nil else { return .nothing }
            return Resolved(text: pair(left, total, figures, style), severityFraction: creditUsedShare)

        case .consumedOfAvailable:
            guard let used = figures.creditUsed, let total = figures.creditTotal, creditUsedShare != nil else { return .nothing }
            return Resolved(text: pair(used, total, figures, style), severityFraction: creditUsedShare)

        case .promoLeft:
            guard let left = figures.promoLeft else { return .nothing }
            return Resolved(text: money(left, figures, style), severityFraction: promoUsedShare)

        case .prepaidLeft:
            // A balance with nothing to measure it against: no tint.
            guard let left = figures.prepaidLeft else { return .nothing }
            return Resolved(text: money(left, figures, style), severityFraction: nil)

        case .leftUnderUserLimit:
            guard let left = figures.leftToSpend else { return .nothing }
            return Resolved(text: money(left, figures, style), severityFraction: leftToSpendShare)

        case .leftOfUserLimit:
            guard let left = figures.leftToSpend, let limit = figures.userLimit, leftToSpendShare != nil else { return .nothing }
            return Resolved(text: pair(left, limit, figures, style), severityFraction: leftToSpendShare)

        case .consumed:
            guard let spent = figures.spent else { return .nothing }
            return Resolved(text: money(spent, figures, style), severityFraction: spentShare)

        case .consumedOfUserLimit:
            guard let spent = figures.spent, let limit = figures.userLimit, spentShare != nil else { return .nothing }
            return Resolved(text: pair(spent, limit, figures, style), severityFraction: spentShare)

        case .pendingInvoice:
            guard let invoice = figures.pendingInvoice else { return .nothing }
            return Resolved(text: money(invoice, figures, style), severityFraction: nil)
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
