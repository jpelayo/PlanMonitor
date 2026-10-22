import Foundation

nonisolated enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case grok
    case openrouter
    /// Providers added later are declared last, newest at the end, on purpose: status items are
    /// created from `allCases.reversed()` with AppKit inserting at the left edge, so the last case
    /// lands rightmost — and existing users' items keep their order.
    case claudeapi
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .openrouter: "OpenRouter"
        case .claudeapi: "Claude-API"
        case .opencode: "OpenCode"
        }
    }
}
