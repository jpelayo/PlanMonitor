import Foundation

/// One workspace member's monthly budget, as `GET /api/v1/budgets/members` reports it.
nonisolated struct OpenCodeMemberBudget: Codable, Equatable, Sendable, Identifiable {
    var userID: String
    var email: String?
    /// This calendar month's spend that counts toward budgets, in dollars.
    var spent: Decimal?
    /// The member's monthly budget in dollars; `nil` means unlimited.
    var budget: Decimal?
    var exceeded: Bool
    /// The start of the next UTC month.
    var resetsAt: Date?
    var source: OpenCodeSnapshot.BudgetSource?

    var id: String { userID }
}

/// Everything the OpenCode dropdown and menu-bar label draw, from one poll of two endpoints:
///
/// - **Go** — the subscription's 5-hour, weekly and monthly windows, from the inference backend.
/// - **Console spend** — this month's spend against the member's budget, from the Console API.
///   Budgets count paid Console models, own providers with a price, web search and Go extra usage
///   paid from credits; **not** Go usage within the plan, and not free models.
///
/// Every figure is optional, and `nil` means "not reported", never zero.
nonisolated struct OpenCodeSnapshot: Codable, Equatable, Sendable {
    nonisolated enum BudgetSource: String, Codable, Sendable {
        /// The member has a limit of their own.
        case custom
        /// The member inherits the workspace's default user budget.
        case `default`
    }

    /// The Go subscription's windows. `nil` when the workspace has no Go subscription or the key
    /// cannot read it.
    var go: OpenCodeGoUsage?

    /// The key could read budgets. `false` after a 403: a key without Budgets › Read.
    var budgetsReadable: Bool
    /// Whose budget this is. `nil` when the figures are the workspace's summed spend.
    var memberEmail: String?
    var spent: Decimal?
    var budget: Decimal?
    var exceeded: Bool
    var resetsAt: Date?
    var budgetSource: BudgetSource?
    /// How many members the workspace reported.
    var memberCount: Int
    /// Several members, and none chosen in Settings: `spent` is everyone's, and no one budget
    /// applies to it.
    var isWorkspaceTotal: Bool
    var fetchedAt: Date?

    static let empty = OpenCodeSnapshot(
        go: nil,
        budgetsReadable: true,
        memberEmail: nil,
        spent: nil,
        budget: nil,
        exceeded: false,
        resetsAt: nil,
        budgetSource: nil,
        memberCount: 0,
        isWorkspaceTotal: false,
        fetchedAt: nil
    )

    var isEmpty: Bool { self == .empty }

    /// Whether the Console spend section has anything to draw.
    var hasSpend: Bool { budgetsReadable && memberCount > 0 }

    /// Spent against the budget. May exceed 1.
    var usedFraction: Double? {
        OpenCodeMoney.usedFraction(spent: spent, budget: budget)
    }

    /// The budget minus what is spent, never below zero.
    var leftUnderBudget: Decimal? {
        guard let budget, let spent else { return nil }
        return max(0, budget - spent)
    }

    /// Picks whose budget to show. A personal key acts as its member, but the endpoint lists every
    /// member and no endpoint says which one is "me". One member is unambiguous; with several, the
    /// one chosen in Settings, and until then the workspace's summed spend against no budget —
    /// never somebody else's limit presented as the user's. `members == nil` means the key could
    /// not read budgets at all.
    static func assemble(
        members: [OpenCodeMemberBudget]?,
        go: OpenCodeGoUsage? = nil,
        selectedMemberID: String?,
        fetchedAt: Date
    ) -> OpenCodeSnapshot {
        guard let members else {
            var unreadable = OpenCodeSnapshot.empty
            unreadable.go = go
            unreadable.budgetsReadable = false
            unreadable.fetchedAt = fetchedAt
            return unreadable
        }

        let member: OpenCodeMemberBudget? = members.count == 1
            ? members.first
            : members.first { $0.userID == selectedMemberID }

        if let member {
            return OpenCodeSnapshot(
                go: go,
                budgetsReadable: true,
                memberEmail: member.email,
                spent: member.spent,
                budget: member.budget,
                exceeded: member.exceeded,
                resetsAt: member.resetsAt,
                budgetSource: member.source,
                memberCount: members.count,
                isWorkspaceTotal: false,
                fetchedAt: fetchedAt
            )
        }

        let reported = members.compactMap(\.spent)
        return OpenCodeSnapshot(
            go: go,
            budgetsReadable: true,
            memberEmail: nil,
            spent: reported.isEmpty ? nil : reported.reduce(0, +),
            budget: nil,
            exceeded: false,
            resetsAt: members.lazy.compactMap(\.resetsAt).first,
            budgetSource: nil,
            memberCount: members.count,
            isWorkspaceTotal: !members.isEmpty,
            fetchedAt: fetchedAt
        )
    }

    /// The next snapshot from one poll. A half that failed transiently keeps the previous figures —
    /// stale beats nothing — while a half the key cannot read is cleared.
    static func merging(
        previous: OpenCodeSnapshot,
        members: OpenCodePollHalf<[OpenCodeMemberBudget]>,
        go: OpenCodePollHalf<OpenCodeGoUsage>,
        selectedMemberID: String?,
        fetchedAt: Date
    ) -> OpenCodeSnapshot {
        var next: OpenCodeSnapshot
        switch members {
        case .read(let rows):
            next = assemble(members: rows, selectedMemberID: selectedMemberID, fetchedAt: fetchedAt)
        case .unreadable:
            next = assemble(members: nil, selectedMemberID: selectedMemberID, fetchedAt: fetchedAt)
        case .unchanged:
            next = previous
        }
        switch go {
        case .read(let usage): next.go = usage
        case .unreadable: next.go = nil
        case .unchanged: next.go = previous.go
        }
        next.fetchedAt = fetchedAt
        return next
    }
}
