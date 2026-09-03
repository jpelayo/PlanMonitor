import Foundation

/// What a provider found when it looked for a stored credential at startup. `unavailable`
/// is the case the old code collapsed into "absent": the secret exists but the Keychain
/// would not hand it over right now. It must keep the cached display and try again later,
/// never show the sign-in wall.
nonisolated enum CredentialRestoreResult: Sendable, Equatable {
    case absent
    case restored(identity: String?)
    case unavailable
}

/// Thrown when a provider answers 200 with a body that does not carry the identity we
/// expect. That is a schema drift or a captive portal, not a rejection — credentials stay.
nonisolated enum IdentityError: Error, Sendable {
    case malformedResponse
}
