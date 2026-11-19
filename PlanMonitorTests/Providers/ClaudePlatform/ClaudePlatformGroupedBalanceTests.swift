import Foundation
import Testing
@testable import PlanMonitor

/// Claude-API's lines in the grouped dropdown's Balances block: credit left (promotional and
/// prepaid) and, only when reported, what awaits invoicing. A missing figure is no line, never 0.
@Suite("Claude-API grouped balance")
@MainActor
struct ClaudePlatformGroupedBalanceTests {
    private func snapshot(promo: Int? = nil, prepaid: Int? = nil, invoice: Int? = nil) -> ClaudePlatformSnapshot {
        var snapshot = ClaudePlatformSnapshot.empty
        snapshot.currency = "USD"
        snapshot.promoGranted = promo
        snapshot.promoRemaining = promo
        snapshot.prepaidRemaining = prepaid
        snapshot.pendingInvoice = invoice
        return snapshot
    }

    @Test func creditLeftAddsPromotionalAndPrepaid() throws {
        let source = snapshot(promo: 15_000, prepaid: 3_000)
        let lines = ClaudePlatformGroupedBalance.lines(snapshot: source, isSignedIn: true, style: .default)
        let line = try #require(lines.first)
        #expect(lines.map(\.id) == ["claudeapi.creditLeft"])
        #expect(line.amount == source.format(18_000, style: .default))
        #expect(line.amount.contains("180"))
        #expect(!line.critical)
    }

    @Test func aPendingInvoiceIsItsOwnLine() {
        let lines = ClaudePlatformGroupedBalance.lines(snapshot: snapshot(invoice: 310), isSignedIn: true, style: .default)
        #expect(lines.map(\.id) == ["claudeapi.pendingInvoice"])
    }

    @Test func bothWhenBothAreReported() {
        let lines = ClaudePlatformGroupedBalance.lines(snapshot: snapshot(prepaid: 500, invoice: 310), isSignedIn: true, style: .default)
        #expect(lines.map(\.id) == ["claudeapi.creditLeft", "claudeapi.pendingInvoice"])
    }

    @Test func nothingReportedNothingShown() {
        #expect(ClaudePlatformGroupedBalance.lines(snapshot: snapshot(), isSignedIn: true, style: .default).isEmpty)
    }

    @Test func signedOutShowsNoFigure() {
        #expect(ClaudePlatformGroupedBalance.lines(snapshot: snapshot(prepaid: 500, invoice: 310), isSignedIn: false, style: .default).isEmpty)
    }

    @Test func noCreditLeftIsCritical() throws {
        let line = try #require(ClaudePlatformGroupedBalance.lines(snapshot: snapshot(promo: 0), isSignedIn: true, style: .default).first)
        #expect(line.critical)
    }
}
