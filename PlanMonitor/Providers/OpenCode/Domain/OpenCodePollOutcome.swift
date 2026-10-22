import Foundation

/// What one poll learned about one half of the snapshot.
nonisolated enum OpenCodePollHalf<Value: Sendable & Equatable>: Sendable, Equatable {
    case read(Value)
    /// The key may not read this half (403), or the workspace has nothing there — no Go
    /// subscription. Cleared from the snapshot, never shown as an error.
    case unreadable
    /// A transient failure: keep what is on screen.
    case unchanged

    var isRead: Bool {
        if case .read = self { return true }
        return false
    }
}

/// One poll of both endpoints, reduced to what the view model applies.
nonisolated struct OpenCodePollOutcome: Sendable, Equatable {
    var members: OpenCodePollHalf<[OpenCodeMemberBudget]>
    var go: OpenCodePollHalf<OpenCodeGoUsage>
    var fetchedAt: Date

    /// The rules, in order:
    /// 1. A 401 from either endpoint is definitive: the key is revoked or expired.
    /// 2. A cycle must read at least one half to count. Otherwise a transient error backs off,
    ///    and a key that can read neither half is refused.
    /// 3. One half failing never blanks the other.
    static func make(
        members: Result<[OpenCodeMemberBudget], OpenCodeAPIError>,
        go: Result<OpenCodeGoUsage?, OpenCodeAPIError>,
        fetchedAt: Date
    ) -> Result<OpenCodePollOutcome, OpenCodeAPIError> {
        var transient: OpenCodeAPIError?
        var definitive: OpenCodeAPIError?

        func classify(_ error: OpenCodeAPIError) {
            if error.isTransient {
                transient = transient ?? error
            } else if error != .missingScope {
                definitive = definitive ?? error
            }
        }

        let membersHalf: OpenCodePollHalf<[OpenCodeMemberBudget]>
        switch members {
        case .success(let rows):
            membersHalf = .read(rows)
        case .failure(let error):
            classify(error)
            membersHalf = error.isTransient ? .unchanged : .unreadable
        }

        let goHalf: OpenCodePollHalf<OpenCodeGoUsage>
        switch go {
        case .success(let usage):
            goHalf = usage.map { .read($0) } ?? .unreadable
        case .failure(let error):
            classify(error)
            goHalf = error.isTransient ? .unchanged : .unreadable
        }

        if let definitive { return .failure(definitive) }
        guard membersHalf.isRead || goHalf.isRead else {
            return .failure(transient ?? .missingScope)
        }
        return .success(OpenCodePollOutcome(members: membersHalf, go: goHalf, fetchedAt: fetchedAt))
    }
}
