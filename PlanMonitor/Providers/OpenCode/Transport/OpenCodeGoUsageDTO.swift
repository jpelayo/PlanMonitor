import Foundation

/// `GET https://opencode.ai/inference/go/v1/usage`, captured 2026-10-22:
///
///     {"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"2026-10-22T22:29:03.000Z"},
///               "weekly":{"status":"ok","percent":0,"resetsAt":"2026-10-26T00:00:00.000Z"},
///               "monthly":{"status":"ok","percent":0,"resetsAt":"2026-11-22T16:42:21.000Z"}}}
///
/// The old open-source console routed `GET /zen/go/v1/usage` here (`inference-proxy.ts`), and its
/// `subscription.ts` names the statuses: `"ok"` and `"rate-limited"`. Every field is optional; a
/// window without a percentage is not reported rather than read as 0%.
nonisolated struct OpenCodeGoUsageResponse: Decodable, Sendable {
    let usage: Windows?

    nonisolated struct Windows: Decodable, Sendable {
        let rolling: Window?
        let weekly: Window?
        let monthly: Window?
    }

    nonisolated struct Window: Decodable, Sendable {
        let status: String?
        let percent: Double?
        let resetsAt: String?

        private enum CodingKeys: String, CodingKey {
            case status, percent, resetsAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
            if let number = try? container.decodeIfPresent(Double.self, forKey: .percent) {
                percent = number
            } else if let string = try? container.decodeIfPresent(String.self, forKey: .percent) {
                percent = Double(string)
            } else {
                percent = nil
            }
        }

        var window: OpenCodeGoWindow? {
            guard let percent, percent.isFinite else { return nil }
            return OpenCodeGoWindow(
                status: status,
                percent: percent,
                resetsAt: resetsAt.flatMap(OpenCodeMemberBudgetDTO.date(from:))
            )
        }
    }

    /// `nil` when no window was reported — a workspace without Go, as far as the app can tell.
    var goUsage: OpenCodeGoUsage? {
        guard let usage else { return nil }
        let result = OpenCodeGoUsage(
            rolling: usage.rolling?.window,
            weekly: usage.weekly?.window,
            monthly: usage.monthly?.window
        )
        return result.isEmpty ? nil : result
    }
}
