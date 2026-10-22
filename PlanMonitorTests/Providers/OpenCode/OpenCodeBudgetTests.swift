import AppKit
import Foundation
import Testing
@testable import PlanMonitor

/// The money arithmetic, whose budget is shown, and every menu-bar choice. The Console reports
/// microcents in decimal strings, so the places a silent change would misreport money are the
/// conversion and the difference between "no budget" and a $0 one.
@Suite("OpenCode budget")
struct OpenCodeBudgetTests {
    private static let fetchedAt = Date(timeIntervalSince1970: 1_792_000_000)

    private static func member(_ id: String, spent: String?, budget: String?, exceeded: Bool = false) -> OpenCodeMemberBudget {
        OpenCodeMemberBudget(
            userID: id,
            email: "\(id)@example.com",
            spent: spent.map(OpenCodeFixtures.decimal),
            budget: budget.map(OpenCodeFixtures.decimal),
            exceeded: exceeded,
            resetsAt: OpenCodeFixtures.utc("2026-11-01T00:00:00Z"),
            source: budget == nil ? nil : .custom
        )
    }

    // MARK: - Microcents

    @Test func microcentsConvertExactly() {
        #expect(OpenCodeMoney.dollars(fromMicroCents: "7525000000") == OpenCodeFixtures.decimal("75.25"))
        #expect(OpenCodeMoney.dollars(fromMicroCents: "1250000000") == OpenCodeFixtures.decimal("12.5"))
        // One microcent survives: Decimal, not cents or Double.
        #expect(OpenCodeMoney.dollars(fromMicroCents: "1") == OpenCodeFixtures.decimal("0.00000001"))
        #expect(OpenCodeMoney.dollars(fromMicroCents: "0") == 0)
    }

    @Test func anythingButADecimalNumberIsNotReported() {
        #expect(OpenCodeMoney.dollars(fromMicroCents: nil) == nil)
        #expect(OpenCodeMoney.dollars(fromMicroCents: "") == nil)
        // `Decimal(string:)` alone would read this as 12.
        #expect(OpenCodeMoney.dollars(fromMicroCents: "12abc") == nil)
        #expect(OpenCodeMoney.dollars(fromMicroCents: "1,000") == nil)
    }

    /// Platform rule: a dot whatever the locale, no thousands separator, two decimals.
    @Test func amountsFollowThePlatformNumberRule() {
        #expect(OpenCodeMoney.format(OpenCodeFixtures.decimal("1234.5"), style: .signAfter) == "1234.50$")
        #expect(OpenCodeMoney.format(OpenCodeFixtures.decimal("0.016"), style: .codeAfter) == "0.02 USD")
        #expect(OpenCodeMoney.format(OpenCodeFixtures.decimal("-0.001"), style: .signAfter) == "0.00$")
        #expect(OpenCodeMoney.formatMenuBar(OpenCodeFixtures.decimal("12.99"), style: .signBefore) == "$12")
        #expect(OpenCodeMoney.formatMenuBar(OpenCodeFixtures.decimal("99960"), style: .codeAfter) == "99.9k USD")
        #expect(OpenCodeMoney.formatMenuBar(OpenCodeFixtures.decimal("9999.99"), style: .none) == "9999")
    }

    // MARK: - Whose budget

    @Test func oneMemberIsUnambiguous() throws {
        let snapshot = OpenCodeSnapshot.assemble(
            members: try OpenCodeFixtures.members(OpenCodeFixtures.docsExample),
            selectedMemberID: nil,
            fetchedAt: Self.fetchedAt
        )
        #expect(snapshot.memberEmail == "alice@example.com")
        #expect(snapshot.spent == OpenCodeFixtures.decimal("12.5"))
        #expect(snapshot.budget == OpenCodeFixtures.decimal("75.25"))
        #expect(snapshot.budgetSource == .custom)
        #expect(!snapshot.isWorkspaceTotal)
        #expect(snapshot.memberCount == 1)
    }

    /// Several members and no choice yet: everyone's spend, and nobody's limit presented as the
    /// user's.
    @Test func severalMembersWithoutAChoiceShowTheWorkspaceTotal() {
        let members = [
            Self.member("a", spent: "10", budget: "50"),
            Self.member("b", spent: "2.5", budget: nil)
        ]
        let snapshot = OpenCodeSnapshot.assemble(members: members, selectedMemberID: nil, fetchedAt: Self.fetchedAt)

        #expect(snapshot.isWorkspaceTotal)
        #expect(snapshot.spent == OpenCodeFixtures.decimal("12.5"))
        #expect(snapshot.budget == nil)
        #expect(snapshot.memberEmail == nil)
        #expect(snapshot.memberCount == 2)
    }

    @Test func theChosenMemberIsShown() {
        let members = [
            Self.member("a", spent: "10", budget: "50"),
            Self.member("b", spent: "2.5", budget: nil)
        ]
        let snapshot = OpenCodeSnapshot.assemble(members: members, selectedMemberID: "a", fetchedAt: Self.fetchedAt)

        #expect(!snapshot.isWorkspaceTotal)
        #expect(snapshot.memberEmail == "a@example.com")
        #expect(snapshot.budget == OpenCodeFixtures.decimal("50"))
    }

    @Test func aChoiceThatLeftTheWorkspaceFallsBackToTheTotal() {
        let members = [Self.member("a", spent: "1", budget: nil), Self.member("b", spent: "1", budget: nil)]
        let snapshot = OpenCodeSnapshot.assemble(members: members, selectedMemberID: "gone", fetchedAt: Self.fetchedAt)
        #expect(snapshot.isWorkspaceTotal)
    }

    // MARK: - What is left

    @Test func whatIsLeftOfTheBudgetNeverGoesNegative() {
        var snapshot = OpenCodeSnapshot.empty
        snapshot.spent = OpenCodeFixtures.decimal("12.5")
        snapshot.budget = OpenCodeFixtures.decimal("75.25")
        #expect(snapshot.leftUnderBudget == OpenCodeFixtures.decimal("62.75"))

        snapshot.spent = OpenCodeFixtures.decimal("80")
        #expect(snapshot.leftUnderBudget == 0)

        snapshot.budget = nil
        #expect(snapshot.leftUnderBudget == nil)
    }

    // MARK: - Ring and severity

    @Test func theBudgetRingFillsWithWhatIsLeft() throws {
        let snapshot = OpenCodeSnapshot.assemble(
            members: try OpenCodeFixtures.members(OpenCodeFixtures.docsExample),
            selectedMemberID: nil,
            fetchedAt: Self.fetchedAt
        )
        #expect(OpenCodeRingSource.off.fill(for: snapshot) == nil)
        // 1 − 12.5/75.25 ≈ 0.834, quantised to ten dashes of twelve.
        #expect(OpenCodeRingSource.budget.fill(for: snapshot) == 10.0 / 12.0)

        let unlimited = OpenCodeSnapshot.assemble(
            members: try OpenCodeFixtures.members(OpenCodeFixtures.captured),
            selectedMemberID: nil,
            fetchedAt: Self.fetchedAt
        )
        #expect(OpenCodeRingSource.budget.fill(for: unlimited) == nil)
    }

    /// The API says the budget is reached: the icon turns red whatever the arithmetic says.
    @Test func aReachedBudgetIsCritical() {
        var snapshot = OpenCodeSnapshot.assemble(
            members: [Self.member("a", spent: "10", budget: "75", exceeded: true)],
            selectedMemberID: nil,
            fetchedAt: Self.fetchedAt
        )
        snapshot.exceeded = true
        let label = OpenCodeMenuBarLabel.make(
            snapshot: snapshot,
            connectionState: .connected(keyPrefix: "oc_sk_0123456789ab"),
            display: .goRolling,
            showRemainingPercent: false,
            ringFill: nil,
            font: MenuBarLabel.defaultFont
        )
        #expect(label.symbolTint == .systemRed)
        // No Go subscription here: a Go choice draws nothing rather than money or `0%`.
        #expect(label.text == nil)
    }

    // MARK: - The key

    @Test func onlyTheKeysPublicPrefixIsEverShown() {
        #expect(OpenCodeAPIKey.prefix(of: OpenCodeFixtures.testKey) == "oc_sk_0123456789ab")
        // An underscore inside the secret stays in the secret.
        #expect(OpenCodeAPIKey.prefix(of: "oc_sk_0123456789ab_abc_def") == "oc_sk_0123456789ab")
        #expect(OpenCodeAPIKey(key: "  \(OpenCodeFixtures.testKey)\n").prefix == "oc_sk_0123456789ab")
    }

    @Test func keysOfAnotherShapeAreRefusedBeforeAnyRequest() {
        #expect(OpenCodeAPIKey.looksValid(OpenCodeFixtures.testKey))
        #expect(!OpenCodeAPIKey.looksValid("sk-or-v1-0123456789abcdef0123"))
        #expect(!OpenCodeAPIKey.looksValid("oc_sk_"))
        #expect(!OpenCodeAPIKey.looksValid("oc_sk_0123456789ab"))
        #expect(!OpenCodeAPIKey.looksValid("oc_sk_0123456789ab_"))
    }
}
