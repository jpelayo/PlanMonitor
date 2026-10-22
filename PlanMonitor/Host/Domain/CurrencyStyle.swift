import Foundation

/// How a money provider writes the currency beside an amount, in its menu-bar item and its dropdown
/// alike. OpenRouter, Claude-API and OpenCode each keep their own choice, `<provider>.currencyStyle`,
/// set in Settings (user decision, 2026-10-14).
///
/// The labels use the user's words: the **symbol** is the ISO code (`USD`), the **character** the
/// currency sign (`$`). The cases are named for what they print.
///
/// The currency is whatever the provider's API reports. When it reports none, nothing is written
/// beside the amount whatever the style — a currency is never assumed here; a provider that wants a
/// fallback (OpenRouter's credits are USD) passes it in itself.
nonisolated enum CurrencyStyle: String, CaseIterable, Sendable {
    case none
    case codeBefore
    case codeAfter
    case signBefore
    case signAfter

    /// The character after the amount, flush: `180$`.
    static let `default` = CurrencyStyle.signAfter

    /// Each label carries an example, so "symbol" and "character" need no explaining.
    var displayName: String {
        switch self {
        case .none: String(localized: "None (180)")
        case .codeBefore: String(localized: "Symbol before (USD 180)")
        case .codeAfter: String(localized: "Symbol after (180 USD)")
        case .signBefore: String(localized: "Character before ($180)")
        case .signAfter: String(localized: "Character after (180$)")
        }
    }

    /// Writes `currency` beside an already formatted amount (`"180.06"`, `"-4"`, `"12.5k"`, or a
    /// pair like `"19/200"`). The character sits flush against the number; the code is set off by
    /// a space. A leading minus stays outermost, so a deficit reads `-$4`, not `$-4`.
    func apply(to number: String, currency: String?) -> String {
        guard self != .none, let currency, !currency.isEmpty else { return number }
        let isNegative = number.hasPrefix("-")
        let sign = isNegative ? "-" : ""
        let magnitude = isNegative ? String(number.dropFirst()) : number

        switch self {
        case .none: return number
        case .codeBefore: return "\(sign)\(currency) \(magnitude)"
        case .codeAfter: return "\(number) \(currency)"
        case .signBefore: return sign + Self.sign(for: currency) + magnitude
        case .signAfter: return number + Self.sign(for: currency)
        }
    }

    /// The narrow sign for an ISO 4217 code — `$` for USD, `€` for EUR, `£` for GBP — or the code
    /// itself when the system knows no sign for it.
    static func sign(for currency: String) -> String {
        let sample = Decimal(0).formatted(
            .currency(code: currency).presentation(.narrow).locale(Locale(identifier: "en_US"))
        )
        let sign = sample.filter { !$0.isNumber && $0 != "." && $0 != "," && !$0.isWhitespace }
        return sign.isEmpty ? currency : sign
    }
}
