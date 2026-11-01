import Foundation

/// What the Claude-API menu-bar item shows. Rebuilt on 2026-11-01 (user decision) after "available
/// minus consumed" read 199$ for an account holding 31.87$: the old list paired the promotional
/// grant with this month's spend, which resets on the 1st while the grant's use does not.
///
/// Two families, each read from its own source:
///
/// - **credit** — what the account holds, from the balances themselves: promotional plus prepaid
///   (`creditLeft`), against the promotional grant plus the prepaid balance (`creditTotal`);
/// - **spend** — this month's spend against the spend limit the account set itself
///   (`notify_and_pause`). What is left to spend is capped at the credit left when a pre-paid
///   account is not topped up automatically, because requests stop there.
///
/// The raw values of the eight choices from 2026-10-14 are kept, so a saved choice survives; their
/// labels say what they now count. Money only, never percentages (user decision, 2026-10-14). A `/`
/// separates two amounts, so "credit left / total credit" reads `31/200$`.
///
/// Not `MenuBarUsageDisplay`: that one is the shared five-hour/weekly selector for the percentage
/// providers. This provider shows money, so it owns its own picker, exactly as OpenRouter does.
nonisolated enum ClaudePlatformMenuBarDisplay: String, CaseIterable, Sendable {
    case iconOnly
    // Credit
    case left
    case leftOfAvailable
    case consumedOfAvailable
    case promoLeft
    case prepaidLeft
    // Spend
    case leftUnderUserLimit
    case leftOfUserLimit
    case consumed
    case consumedOfUserLimit
    case pendingInvoice

    /// What can still be spent before the account's own limit, never more than the credit left
    /// when spending stops there (user decisions, 2026-10-14 and 2026-11-01). With no own limit set
    /// it draws nothing, like any choice whose figures are not reported.
    static let `default` = ClaudePlatformMenuBarDisplay.leftUnderUserLimit

    var displayName: String {
        switch self {
        case .iconOnly: String(localized: "Icon only")
        case .left: String(localized: "Credit left")
        case .leftOfAvailable: String(localized: "Credit left / total credit")
        case .consumedOfAvailable: String(localized: "Credit used / total credit")
        case .promoLeft: String(localized: "Promotional credit left")
        case .prepaidLeft: String(localized: "Prepaid credit left")
        case .leftUnderUserLimit: String(localized: "Left to spend")
        case .leftOfUserLimit: String(localized: "Left to spend / your limit")
        case .consumed: String(localized: "Spend this month")
        case .consumedOfUserLimit: String(localized: "Spend this month / your limit")
        case .pendingInvoice: String(localized: "To be invoiced")
        }
    }
}
