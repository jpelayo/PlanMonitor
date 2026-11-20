import Foundation
import Testing
@testable import PlanMonitor

/// OpenRouter's line in the grouped dropdown's Balances block: its own figure, its own style.
@Suite("OpenRouter grouped balance")
@MainActor
struct OpenRouterGroupedBalanceTests {
    private let identity = KeyIdentity(label: "k", isManagementKey: true, isFreeTier: false, expiresAt: nil)

    private func snapshot(purchased: Decimal, used: Decimal) -> OpenRouterSnapshot {
        var snapshot = OpenRouterSnapshot.empty
        snapshot.accountCredit = AccountCredit(totalPurchased: purchased, totalUsed: used)
        return snapshot
    }

    @Test func theCreditLeftIsWrittenInOpenRoutersStyle() throws {
        let lines = OpenRouterGroupedBalance.lines(
            snapshot: snapshot(purchased: 50, used: Decimal(string: "37.66", locale: Locale(identifier: "en_US_POSIX"))!),
            connectionState: .connected(identity),
            style: .codeBefore
        )
        let line = try #require(lines.first)
        #expect(lines.count == 1)
        #expect(line.amount == Money.format(Decimal(string: "12.34", locale: Locale(identifier: "en_US_POSIX"))!, style: .codeBefore))
        #expect(line.amount?.contains("12.34") == true)
        #expect(line.action == nil)
        #expect(!line.critical)
    }

    @Test func anOverdrawnAccountIsCritical() throws {
        let line = try #require(OpenRouterGroupedBalance.lines(
            snapshot: snapshot(purchased: 10, used: 12),
            connectionState: .connected(identity),
            style: .default
        ).first)
        #expect(line.critical)
    }

    @Test func noCreditNoLine() {
        #expect(OpenRouterGroupedBalance.lines(snapshot: .empty, connectionState: .connected(identity), style: .default).isEmpty)
    }

    @Test func disconnectedIsTheNameAndConnect() throws {
        let lines = OpenRouterGroupedBalance.lines(snapshot: snapshot(purchased: 50, used: 10), connectionState: .disconnected, style: .default)
        let line = try #require(lines.first)
        #expect(lines.count == 1)
        #expect(line.amount == nil)
        #expect(line.action == BalanceAction(title: String(localized: "Connect"), window: .connectOpenRouter))
    }

    @Test func aRefusedKeyShowsNoFigureOnlyReplaceKey() throws {
        let lines = OpenRouterGroupedBalance.lines(snapshot: snapshot(purchased: 50, used: 10), connectionState: .invalidKey("refused"), style: .default)
        let line = try #require(lines.first)
        #expect(lines.count == 1)
        #expect(line.amount == nil)
        #expect(line.action == BalanceAction(title: String(localized: "Replace key"), window: .connectOpenRouter))
    }

    @Test func validatingShowsNothing() {
        #expect(OpenRouterGroupedBalance.lines(snapshot: snapshot(purchased: 50, used: 10), connectionState: .validating, style: .default).isEmpty)
    }
}
