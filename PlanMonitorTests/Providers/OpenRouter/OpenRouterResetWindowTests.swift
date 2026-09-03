import Foundation
import Testing
@testable import PlanTracker

private func utc(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: string)!
}

private func iso(_ date: Date?) -> String? {
    guard let date else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
}

@Suite("Reset window arithmetic (UTC)")
struct ResetWindowTests {

    @Test("Daily resets at the next 00:00 UTC")
    func daily() {
        let window = ResetWindowCalculator.window(for: .daily, now: utc("2026-08-27 14:32:10"))
        #expect(iso(window.windowStart) == "2026-08-27 00:00:00")
        #expect(iso(window.nextReset) == "2026-08-28 00:00:00")
    }

    /// OpenRouter weeks start Monday. A Sunday must belong to the week that began the
    /// preceding Monday — the classic off-by-one if firstWeekday is left at Sunday.
    @Test("Weekly windows start Monday, and Sunday belongs to the prior Monday")
    func weeklyStartsMonday() {
        // 2026-08-30 is a Sunday; its week began Monday 2026-08-24.
        let sunday = ResetWindowCalculator.window(for: .weekly, now: utc("2026-08-30 23:00:00"))
        #expect(iso(sunday.windowStart) == "2026-08-24 00:00:00")
        #expect(iso(sunday.nextReset) == "2026-08-31 00:00:00")

        // 2026-08-31 is the following Monday and starts a new window.
        let monday = ResetWindowCalculator.window(for: .weekly, now: utc("2026-08-31 00:00:01"))
        #expect(iso(monday.windowStart) == "2026-08-31 00:00:00")
    }

    @Test("Monthly resets on the 1st of the next month")
    func monthly() {
        let window = ResetWindowCalculator.window(for: .monthly, now: utc("2026-08-27 14:32:10"))
        #expect(iso(window.windowStart) == "2026-08-01 00:00:00")
        #expect(iso(window.nextReset) == "2026-09-01 00:00:00")
    }

    @Test("Month-end rollover crosses the year boundary")
    func decemberRollsToJanuary() {
        let window = ResetWindowCalculator.window(for: .monthly, now: utc("2026-12-31 23:59:59"))
        #expect(iso(window.nextReset) == "2027-01-01 00:00:00")
    }

    @Test("February in a leap year rolls to March 1")
    func leapFebruary() {
        let window = ResetWindowCalculator.window(for: .monthly, now: utc("2028-02-29 12:00:00"))
        #expect(iso(window.windowStart) == "2028-02-01 00:00:00")
        #expect(iso(window.nextReset) == "2028-03-01 00:00:00")
    }

    /// The window is UTC regardless of where the user is. A machine in Auckland must
    /// not shift the boundary — only the rendering is localised.
    @Test("Window is UTC-anchored, not local")
    func utcAnchoredNotLocal() {
        // 13:00 UTC is already the next local day in UTC+13.
        let window = ResetWindowCalculator.window(for: .daily, now: utc("2026-08-27 13:00:00"))
        #expect(iso(window.windowStart) == "2026-08-27 00:00:00")
    }

    @Test("A nil interval is a lifetime cap that never resets")
    func lifetimeCap() {
        let window = ResetWindowCalculator.window(for: nil, now: Date())
        #expect(window.interval == nil)
        #expect(window.nextReset == nil)
        #expect(window.resets == false)
        #expect(ResetFormatter.describe(window) == nil)
    }

    @Test("Next reset is always in the future relative to now")
    func nextResetIsFuture() {
        let now = utc("2026-08-27 14:32:10")
        for interval in ResetInterval.allCases {
            let window = ResetWindowCalculator.window(for: interval, now: now)
            let next = try! #require(window.nextReset)
            #expect(next > now, "\(interval) produced a past reset")
            let start = try! #require(window.windowStart)
            #expect(start <= now, "\(interval) produced a future window start")
        }
    }
}

@Suite("Money")
struct MoneyTests {

    @Test("Sub-half-cent residue displays as zero but is preserved for arithmetic")
    func cosmeticResidue() {
        let residue = Decimal(string: "0.0000004")!
        #expect(Money.displayValue(residue) == 0)
        #expect(residue > 0)          // the real value is untouched
    }

    /// A negative balance is exactly what the user must see. Snapping it to zero would
    /// hide the one state that blocks their account.
    @Test("A negative balance is never snapped to zero")
    func negativeNotSnapped() {
        let overdrawn = Decimal(string: "-3.40")!
        #expect(Money.displayValue(overdrawn) == overdrawn)
    }

    @Test("Sub-cent values survive as Decimal, unlike integer minor units")
    func subCentPrecision() {
        let data = #"{"total_credits":100.5,"total_usage":0.015}"#.data(using: .utf8)!
        let dto = try! JSONDecoder().decode(CreditsDTO.self, from: data)
        #expect(dto.totalUsage == Decimal(string: "0.015")!)
        #expect(dto.totalUsage != 0)
    }

    @Test("Fraction is nil when the limit is zero, never a divide-by-zero")
    func zeroLimitFraction() {
        #expect(Money.fraction(spent: 5, limit: 0) == nil)
        #expect(Money.fraction(spent: 5, limit: -1) == nil)
    }

    @Test("Overspend yields a fraction above 1")
    func overspendFraction() {
        let fraction = try! #require(Money.fraction(spent: 120, limit: 100))
        #expect(abs(fraction - 1.2) < 0.0001)
    }
}

@Suite("Account credit")
struct AccountCreditTests {

    @Test("Remaining is derived and may be negative")
    func negativeRemaining() {
        let credit = AccountCredit(totalPurchased: 10, totalUsed: Decimal(string: "13.40")!)
        #expect(credit.remaining == Decimal(string: "-3.40")!)
        #expect(credit.isNegative)
        // The gauge must read empty, not full, when overdrawn.
        #expect(credit.remainingFraction == 0)
    }

    @Test("Zero purchased yields no fraction rather than a divide-by-zero")
    func zeroPurchased() {
        let credit = AccountCredit(totalPurchased: 0, totalUsed: 0)
        #expect(credit.usedFraction == nil)
        #expect(credit.remainingFraction == nil)
    }

    @Test("Remaining fraction is clamped to 0...1 for the menu-bar ring")
    func remainingFractionClamped() {
        let credit = AccountCredit(totalPurchased: 100, totalUsed: 25)
        #expect(abs((credit.remainingFraction ?? 0) - 0.75) < 0.0001)
    }
}

@Suite("Credit severity")
struct CreditSeverityTests {

    /// The bug this guards against: `total_credits` is lifetime purchases, not a cap,
    /// so spending 86% of it is unremarkable — an account topped up in small amounts
    /// sits near 100% permanently. Feeding that ratio into the budget severity scale
    /// painted a healthy account amber.
    @Test("A high share of lifetime purchases spent is not a warning")
    func lifetimeRatioIsNotSeverity() {
        // The real captured figures that produced a spurious amber ring.
        let credit = AccountCredit(
            totalPurchased: 183,
            totalUsed: Decimal(string: "157.436091917")!
        )
        #expect((credit.usedFraction ?? 0) > 0.85)     // 86% spent...
        #expect(credit.severity == .normal)            // ...and still healthy
    }

    @Test("Credit has no ceiling — only the floor at zero is critical")
    func onlyFloorIsCritical() {
        #expect(AccountCredit(totalPurchased: 100, totalUsed: 99).severity == .normal)
        #expect(AccountCredit(totalPurchased: 100, totalUsed: 100).severity == .critical)
        #expect(AccountCredit(totalPurchased: 100, totalUsed: 120).severity == .critical)
    }

    /// Severity for real budgets is unchanged: those have genuine denominators.
    @Test("Key and guardrail budgets still escalate on their own limits")
    func realBudgetsStillEscalate() {
        #expect(BudgetSeverity(0.50) == .normal)
        #expect(BudgetSeverity(0.70) == .warning)
        #expect(BudgetSeverity(0.95) == .critical)
        #expect(BudgetSeverity(nil) == .normal)
    }
}
