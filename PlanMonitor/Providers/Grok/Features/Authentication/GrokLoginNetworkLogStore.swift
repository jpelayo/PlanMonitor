import Foundation

#if DEBUG
@MainActor
@Observable
final class GrokLoginNetworkLogStore {
    static let shared = GrokLoginNetworkLogStore()

    private static let maxLines = 400

    private(set) var lines: [String] = []

    var text: String { lines.joined(separator: "\n") }

    var fileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = root.appending(path: "PlanTracker", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "login-network.log")
    }

    /// Lines are expected to be pre-redacted by the caller (no query strings or fragments).
    func append(_ line: String) {
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)"
        lines.append(stamped)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
        // Rewrite the whole bounded buffer so the on-disk log can never outgrow it,
        // even across launches.
        let data = (text + "\n").data(using: .utf8) ?? Data()
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        lines = []
        try? FileManager.default.removeItem(at: fileURL)
    }
}
#endif
