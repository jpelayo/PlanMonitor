import Foundation

/// What the Claude-API menu-bar item shows. Eight choices over three sums (user decision,
/// 2026-10-14), replacing an earlier list of eleven that split promotional credit, spend, prepaid
/// credit and invoicing into separate indicators:
///
/// - **total available** — every promotional credit granted plus the paid credit on the books;
/// - **total consumed** — this month's spend, the console's one sum of all consumption, which
///   resets monthly so what is left returns to the full amount;
/// - **your limit** — the spend limit the account set itself (`notify_and_pause`).
///
/// Money only, never percentages (user decision, 2026-10-14). A `/` separates two amounts, so
/// "consumed / available" reads `19/200$`.
///
/// Not `MenuBarUsageDisplay`: that one is the shared five-hour/weekly selector for the percentage
/// providers. This provider shows money, so it owns its own picker, exactly as OpenRouter does.
nonisolated enum ClaudePlatformMenuBarDisplay: String, CaseIterable, Sendable {
    case iconOnly
    case consumed
    case left
    case consumedOfAvailable
    case leftOfAvailable
    case consumedOfUserLimit
    case leftUnderUserLimit
    case leftOfUserLimit

    /// What can still be spent before the account's own limit (user decision, 2026-10-14). With
    /// no own limit set it draws nothing, like any choice whose figures are not reported.
    static let `default` = ClaudePlatformMenuBarDisplay.leftUnderUserLimit

    var displayName: String {
        switch self {
        case .iconOnly: String(localized: "Icon only")
        case .consumed: String(localized: "Total consumed")
        case .left: String(localized: "Total available minus consumed")
        case .consumedOfAvailable: String(localized: "Consumed / available")
        case .leftOfAvailable: String(localized: "(Available − consumed) / available")
        case .consumedOfUserLimit: String(localized: "Consumed / your limit")
        case .leftUnderUserLimit: String(localized: "Your limit minus consumed")
        case .leftOfUserLimit: String(localized: "(Your limit − consumed) / your limit")
        }
    }
}
