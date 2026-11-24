import Foundation

/// `agy -p /usage --output-format json`, as agy 1.5.14 writes it (seen 2026-11-23):
///
///     {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[
///       {"name":"Gemini Models","buckets":[{"id":"gemini-5h","name":"Five Hour Limit Remaining",
///         "window":"5h","remaining_fraction":0.5478,"reset_time":"2026-11-23T18:30:18Z"}, …]}, …]}}}
///
/// Only these fields are read; the report also carries prose and token counts, ignored.
nonisolated struct GoogleAIUsageReportDTO: Decodable, Sendable {
    struct Command: Decodable, Sendable {
        let name: String?
        let data: DataBlock?
    }

    struct DataBlock: Decodable, Sendable {
        let groups: [Group]?
    }

    struct Group: Decodable, Sendable {
        let name: String?
        let buckets: [Bucket]?
    }

    struct Bucket: Decodable, Sendable {
        let id: String?
        let name: String?
        let window: String?
        let remainingFraction: Double?
        let resetTime: String?

        enum CodingKeys: String, CodingKey {
            case id, name, window
            case remainingFraction = "remaining_fraction"
            case resetTime = "reset_time"
        }
    }

    let status: String?
    let command: Command?
}

nonisolated enum GoogleAIUsageReport {
    /// The report, or `reportChanged` when it is not a successful usage report with at least one
    /// readable bucket. A bucket without a finite fraction is left out rather than read as 0.
    static func parse(_ data: Data) throws(GoogleAIRunError) -> GoogleAIUsage {
        let dto: GoogleAIUsageReportDTO
        do {
            dto = try JSONDecoder().decode(GoogleAIUsageReportDTO.self, from: data)
        } catch {
            throw .reportChanged
        }
        guard dto.status == "SUCCESS", dto.command?.name == "usage", let groups = dto.command?.data?.groups else {
            throw .reportChanged
        }

        let parsed: [GoogleAIGroup] = groups.compactMap { group in
            guard let groupName = group.name, !groupName.isEmpty else { return nil }
            let buckets: [GoogleAIBucket] = (group.buckets ?? []).compactMap { bucket in
                guard let id = bucket.id, let fraction = bucket.remainingFraction, fraction.isFinite else { return nil }
                return GoogleAIBucket(
                    id: id,
                    group: groupName,
                    name: bucket.name ?? id,
                    kind: GoogleAIBucket.Kind(window: bucket.window ?? ""),
                    remaining: min(max(fraction, 0), 1),
                    resetsAt: bucket.resetTime.flatMap(date(from:))
                )
            }
            return buckets.isEmpty ? nil : GoogleAIGroup(name: groupName, buckets: buckets)
        }
        guard !parsed.isEmpty else { throw .reportChanged }
        return GoogleAIUsage(groups: parsed)
    }

    private static func date(from text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
