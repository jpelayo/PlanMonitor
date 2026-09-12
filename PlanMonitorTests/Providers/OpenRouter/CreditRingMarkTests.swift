import Foundation
import Testing
@testable import PlanTracker

private func credit(purchased: Double, used: Double) -> AccountCredit {
    AccountCredit(totalPurchased: Decimal(purchased), totalUsed: Decimal(used))
}

private let step = 1.0 / Double(MenuBarUsageRing.steps)

@Suite("Credit ring mark — the balance after the last top-up is 100%")
struct CreditRingMarkTests {
    @Test("The first balance seen becomes the mark and reads full")
    func firstObservationSeeds() {
        let mark = CreditRingMark().observing(credit(purchased: 50, used: 0))
        #expect(mark.mark == 50)
        #expect(mark.lastRemaining == 50)
        #expect(mark.fill(for: credit(purchased: 50, used: 0)) == 1)
    }

    @Test("Spending drains the ring and leaves the mark alone")
    func drainingKeepsTheMark() {
        var mark = CreditRingMark().observing(credit(purchased: 50, used: 0))
        mark = mark.observing(credit(purchased: 50, used: 25))
        #expect(mark.mark == 50)
        #expect(mark.lastRemaining == 25)
        #expect(mark.fill(for: credit(purchased: 50, used: 25)) == 6 * step)
    }

    /// The case that rules out a running maximum: after draining 50 → 10, a $1 top-up must make
    /// $11 the new 100%, not leave the ring at 11/50.
    @Test("Any increase resets the mark to the new balance")
    func topUpResetsTheMark() {
        var mark = CreditRingMark().observing(credit(purchased: 50, used: 0))
        mark = mark.observing(credit(purchased: 50, used: 40))          // remaining 10
        mark = mark.observing(credit(purchased: 51, used: 40))          // remaining 11
        #expect(mark.mark == 11)
        #expect(mark.fill(for: credit(purchased: 51, used: 40)) == 1)
        // Half of the *new* mark, not of the old one.
        #expect(mark.fill(for: credit(purchased: 51, used: 45.5)) == 6 * step)
    }

    @Test("A dollar loaded onto an empty balance reads full")
    func dollarOnEmpty() {
        var mark = CreditRingMark().observing(credit(purchased: 20, used: 20))   // remaining 0
        mark = mark.observing(credit(purchased: 21, used: 20))                   // remaining 1
        #expect(mark.mark == 1)
        #expect(mark.fill(for: credit(purchased: 21, used: 20)) == 1)
    }

    @Test("Overdrawn pins the ring empty whatever the mark")
    func overdrawnIsEmpty() {
        let mark = CreditRingMark().observing(credit(purchased: 50, used: 0))
        #expect(mark.fill(for: credit(purchased: 50, used: 60)) == 0)
    }

    @Test("A zero mark has nothing to measure against")
    func zeroMarkIsNil() {
        let mark = CreditRingMark().observing(credit(purchased: 20, used: 20))
        #expect(mark.mark == 0)
        #expect(mark.fill(for: credit(purchased: 20, used: 20)) == nil)
        #expect(CreditRingMark().fill(for: credit(purchased: 20, used: 5)) == nil)
    }

    @Test("Values above the mark clamp to full rather than overflowing")
    func clampsAboveMark() {
        // A mark can lag a balance only through a bug or a manual edit; still never exceed 1.
        let mark = CreditRingMark(mark: 10, lastRemaining: 10)
        #expect(mark.fill(for: credit(purchased: 30, used: 0)) == 1)
    }

    @Test("Every fill lands on one of the ring's twelve steps")
    func quantised() {
        let mark = CreditRingMark().observing(credit(purchased: 100, used: 0))
        for used in stride(from: 0.0, through: 100.0, by: 0.7) {
            guard let fill = mark.fill(for: credit(purchased: 100, used: used)) else {
                Issue.record("no fill at \(used)"); continue
            }
            let dashes = fill * Double(MenuBarUsageRing.steps)
            #expect(abs(dashes - dashes.rounded()) < 1e-9)
        }
    }

    @Test("Persists exactly and round-trips through defaults")
    func persistsExactly() {
        let defaults = UserDefaults(suiteName: "CreditRingMarkTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let saved = CreditRingMark(mark: Decimal(string: "12.345678")!, lastRemaining: Decimal(string: "0.01")!)
        saved.save(to: defaults)
        #expect(CreditRingMark.load(from: defaults) == saved)

        CreditRingMark().save(to: defaults)
        #expect(CreditRingMark.load(from: defaults) == CreditRingMark())
    }
}

@Suite("Pooled budget fraction — the Limits ring")
struct PooledBudgetFractionTests {
    private func key(_ hash: String, spent: Double, limit: Double) -> KeyBudget {
        KeyBudget(
            keyHash: hash, name: hash, label: hash, disabled: false,
            limit: Decimal(limit), remaining: Decimal(limit - spent), spent: Decimal(spent),
            window: .lifetime, includesBYOK: false,
            usedFraction: spent / limit, isApproximate: false
        )
    }

    private func member(_ hash: String, spent: Double, limit: Double, superseded: Bool = false) -> GuardrailKeyBudget {
        GuardrailKeyBudget(
            guardrailID: "g", keyHash: hash, keyName: hash, keyLabel: hash,
            spent: Decimal(spent), limit: Decimal(limit),
            usedFraction: spent / limit, supersededByKeyLimit: superseded
        )
    }

    private func guardrail(_ members: [GuardrailKeyBudget], limit: Double) -> GuardrailBudget {
        GuardrailBudget(
            id: "g", name: "g", limit: Decimal(limit), window: .lifetime, includesBYOK: false,
            members: members, worstFraction: members.map(\.usedFraction).max() ?? 0
        )
    }

    @Test("Spend is pooled against the sum of every cap")
    func poolsAcrossKeys() {
        var snapshot = OpenRouterSnapshot.empty
        snapshot.keyBudgets = [key("a", spent: 8, limit: 10), key("b", spent: 1, limit: 10), key("c", spent: 2, limit: 10)]
        #expect(snapshot.pooledBudgetFraction.map { abs($0 - 11.0 / 30.0) < 1e-9 } == true)
        // And it is a different number from the tightest single budget.
        #expect(snapshot.worstBudgetFraction == 0.8)
    }

    /// A key under both its own cap and a guardrail is one key with one spend; the pool must not
    /// count its spend twice, nor credit it with the looser cap's headroom.
    @Test("A key under two caps counts once, at the cap that binds it")
    func countsEachKeyOnceAtBindingLimit() {
        var snapshot = OpenRouterSnapshot.empty
        snapshot.keyBudgets = [key("a", spent: 8, limit: 10)]
        snapshot.guardrailBudgets = [guardrail([member("a", spent: 8, limit: 20, superseded: true)], limit: 20)]
        #expect(snapshot.pooledBudgetFraction == 0.8)

        // Guardrail tighter than the key's own cap: the guardrail's limit is the one that binds.
        snapshot.keyBudgets = [key("a", spent: 8, limit: 40)]
        snapshot.guardrailBudgets = [guardrail([member("a", spent: 8, limit: 20)], limit: 20)]
        #expect(snapshot.pooledBudgetFraction == 0.4)
    }

    @Test("Guardrail-only keys join the pool")
    func guardrailMembersCount() {
        var snapshot = OpenRouterSnapshot.empty
        snapshot.keyBudgets = [key("a", spent: 5, limit: 10)]
        snapshot.guardrailBudgets = [guardrail([member("b", spent: 5, limit: 10)], limit: 10)]
        #expect(snapshot.pooledBudgetFraction == 0.5)
    }

    @Test("No capped keys means nothing to gauge")
    func nilWithoutCaps() {
        #expect(OpenRouterSnapshot.empty.pooledBudgetFraction == nil)
    }
}
