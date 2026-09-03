import Foundation

/// The shape of every secret PlanTracker stores. The envelope is provider-neutral; the
/// payload is the provider's own versioned type. On disk this is JSON with ISO-8601 dates and
/// sorted keys, for example:
///
///     {
///       "createdAt": "2026-09-01T10:00:00Z",
///       "format": 1,
///       "kind": "session",
///       "payload": { "cookieHeader": "…", "schemaVersion": 1 },
///       "provider": "codex",
///       "updatedAt": "2026-09-01T10:00:00Z"
///     }
///
/// `format` versions the envelope itself. Each payload carries its own `schemaVersion` so a
/// provider can evolve its secret without touching the envelope or any other provider.
nonisolated struct CredentialEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    static var currentFormat: Int { 1 }

    var format: Int
    var provider: ProviderID
    var kind: String
    var createdAt: Date
    var updatedAt: Date
    var payload: Payload

    init(provider: ProviderID, kind: String, payload: Payload, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.format = Self.currentFormat
        self.provider = provider
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.payload = payload
    }
}

/// A payload that knows its own schema version. Stores branch on this when the type gains
/// fields or changes meaning.
nonisolated protocol VersionedCredentialPayload: Codable, Sendable {
    static var currentSchemaVersion: Int { get }
    var schemaVersion: Int { get }
}

nonisolated enum CredentialCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
