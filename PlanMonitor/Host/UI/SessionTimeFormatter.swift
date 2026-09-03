import Foundation

/// Renders the accumulated session time exactly the way the Claude menu always did:
/// hidden under a minute, `"Today's usage: 1h 23m"` above.
nonisolated enum SessionTimeFormatter {
    static func line(totalSeconds: TimeInterval) -> String? {
        guard totalSeconds >= 60 else { return nil }
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let duration = hours > 0
            ? String(localized: "\(hours)h \(minutes)m")
            : String(localized: "\(minutes)m")
        return String(localized: "Today's usage:") + " " + duration
    }
}
