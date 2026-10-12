import Foundation

/// What the Claude-API menu-bar item shows: one indicator, or two joined by `·`.
///
/// A curated list rather than every pairing of six indicators, which would run past twenty entries.
/// The pairs here are the ones that answer a question together — what is left against what is being
/// spent — and anything else is reachable by picking a single indicator.
///
/// Not `MenuBarUsageDisplay`: that one is the shared five-hour/weekly selector for the percentage
/// providers. This provider shows money, so it owns its own picker, exactly as OpenRouter does.
nonisolated enum ClaudePlatformMenuBarDisplay: String, CaseIterable, Sendable {
    case promoAmount
    case promoPercent
    case spendAmount
    case spendPercent
    case prepaidAmount
    case invoicedAmount
    case promoAndSpendAmount
    case promoAndSpendPercent
    case promoAndPrepaidAmount
    case spendAndInvoicedAmount
    case iconOnly

    /// The promotional balance is the default: it is the thing this provider exists to watch, and it
    /// expires on a clock nothing else in the app tracks.
    static let `default` = ClaudePlatformMenuBarDisplay.promoAmount

    var displayName: String {
        switch self {
        case .promoAmount: String(localized: "Promotional credit amount")
        case .promoPercent: String(localized: "Promotional credit percent")
        case .spendAmount: String(localized: "Spend amount")
        case .spendPercent: String(localized: "Spend percent")
        case .prepaidAmount: String(localized: "Prepaid credit amount")
        case .invoicedAmount: String(localized: "To be invoiced amount")
        case .promoAndSpendAmount: String(localized: "Promotional credit and spend amounts")
        case .promoAndSpendPercent: String(localized: "Promotional credit and spend percents")
        case .promoAndPrepaidAmount: String(localized: "Promotional and prepaid credit amounts")
        case .spendAndInvoicedAmount: String(localized: "Spend and to be invoiced amounts")
        case .iconOnly: String(localized: "Icon only")
        }
    }

    /// The indicators this selection puts on the bar, in the order they are drawn.
    var indicators: [ClaudePlatformIndicator] {
        switch self {
        case .promoAmount: [.promoAmount]
        case .promoPercent: [.promoPercent]
        case .spendAmount: [.spendAmount]
        case .spendPercent: [.spendPercent]
        case .prepaidAmount: [.prepaidAmount]
        case .invoicedAmount: [.invoicedAmount]
        case .promoAndSpendAmount: [.promoAmount, .spendAmount]
        case .promoAndSpendPercent: [.promoPercent, .spendPercent]
        case .promoAndPrepaidAmount: [.promoAmount, .prepaidAmount]
        case .spendAndInvoicedAmount: [.spendAmount, .invoicedAmount]
        case .iconOnly: []
        }
    }
}

/// One figure on the bar.
///
/// Each reads as its own name does: a *credit* indicator shows what is left, a *spend* indicator
/// shows what has gone. Mixing those senses under one global remaining/used switch is why this
/// provider sits out `GlobalPreferences.Change.percentageMode`, as OpenRouter does.
nonisolated enum ClaudePlatformIndicator: Sendable {
    case promoAmount
    case promoPercent
    case spendAmount
    case spendPercent
    case prepaidAmount
    case invoicedAmount
}
