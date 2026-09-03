import Foundation

nonisolated enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case grok
    case openrouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .openrouter: "OpenRouter"
        }
    }
}
