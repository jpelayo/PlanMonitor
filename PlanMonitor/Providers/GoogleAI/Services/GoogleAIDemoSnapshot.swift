import Foundation

/// Deterministic figures for reviewer mode: agy's three groups, the Gemini models part-used.
nonisolated enum GoogleAIDemoSnapshot {
    static func usage(now: Date) -> GoogleAIUsage {
        func bucket(_ id: String, _ group: String, _ kind: GoogleAIBucket.Kind, remaining: Double, resetIn: TimeInterval) -> GoogleAIBucket {
            GoogleAIBucket(id: id, group: group, name: id, kind: kind, remaining: remaining, resetsAt: now.addingTimeInterval(resetIn))
        }
        return GoogleAIUsage(groups: [
            GoogleAIGroup(name: "Gemini Models", buckets: [
                bucket("gemini-weekly", "Gemini Models", .weekly, remaining: 0.70, resetIn: 5 * 86400 + 19 * 3600),
                bucket("gemini-5h", "Gemini Models", .fiveHour, remaining: 0.55, resetIn: 2 * 3600 + 25 * 60)
            ]),
            GoogleAIGroup(name: "Claude and GPT models", buckets: [
                bucket("3p-weekly", "Claude and GPT models", .weekly, remaining: 0.88, resetIn: 3 * 86400 + 4 * 3600),
                bucket("3p-5h", "Claude and GPT models", .fiveHour, remaining: 1, resetIn: 5 * 3600)
            ]),
            GoogleAIGroup(name: "Gemini 4 Argon", buckets: [
                bucket("gemini-argon-wtu-weekly", "Gemini 4 Argon", .weekly, remaining: 1, resetIn: 7 * 86400)
            ])
        ])
    }
}
