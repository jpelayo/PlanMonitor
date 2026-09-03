import Foundation

nonisolated enum GrokCLIAuthImporterError: Error, Equatable, LocalizedError {
    case fileTooLarge
    case unreadableFile
    case invalidJSON
    case missingOIDCRecord
    case unsupportedIssuer
    case unsupportedClientID
    case unsupportedAuthMode
    case missingTokens
    case invalidExpiration

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            String(localized: "The selected file is too large to be a Grok login file.")
        case .unreadableFile:
            String(localized: "Could not read the selected Grok login file.")
        case .invalidJSON:
            String(localized: "The selected file is not valid Grok login JSON.")
        case .missingOIDCRecord:
            String(localized: "No Grok CLI OIDC record was found in the selected file.")
        case .unsupportedIssuer:
            String(localized: "The Grok login file uses an unexpected issuer.")
        case .unsupportedClientID:
            String(localized: "The Grok login file uses an unexpected client ID.")
        case .unsupportedAuthMode:
            String(localized: "The Grok login file is not an OIDC credential.")
        case .missingTokens:
            String(localized: "The Grok login file is missing an access or refresh token.")
        case .invalidExpiration:
            String(localized: "The Grok login file has an invalid token expiration.")
        }
    }
}

nonisolated enum GrokCLIAuthImporter {
    static let maximumFileSize = 1_048_576

    static func importCredentials(from url: URL, now: Date = Date()) throws -> GrokCredentials {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try importCredentials(fromUnscopedURL: url, now: now)
    }

    static func importCredentials(fromUnscopedURL url: URL, now: Date = Date()) throws -> GrokCredentials {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > maximumFileSize {
            throw GrokCLIAuthImporterError.fileTooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw GrokCLIAuthImporterError.unreadableFile
        }
        if data.count > maximumFileSize {
            throw GrokCLIAuthImporterError.fileTooLarge
        }
        return try importCredentials(from: data, now: now)
    }

    static func importCredentials(from data: Data, now: Date = Date()) throws -> GrokCredentials {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GrokCLIAuthImporterError.invalidJSON
        }
        guard let root = object as? [String: Any] else {
            throw GrokCLIAuthImporterError.invalidJSON
        }

        let record = try selectRecord(from: root)
        return try credentials(from: record, now: now)
    }

    private static func selectRecord(from root: [String: Any]) throws -> [String: Any] {
        let expectedPrefix = "\(GrokCredentials.expectedIssuer.absoluteString)::"
        if let nested = root[expectedPrefix + GrokCredentials.expectedClientID] as? [String: Any] {
            return nested
        }
        if root["auth_mode"] != nil {
            return root
        }
        if let match = root.values.compactMap({ $0 as? [String: Any] }).first(where: {
            ($0["oidc_client_id"] as? String) == GrokCredentials.expectedClientID
                || ($0["oidc_issuer"] as? String) == GrokCredentials.expectedIssuer.absoluteString
        }) {
            return match
        }
        throw GrokCLIAuthImporterError.missingOIDCRecord
    }

    private static func credentials(from record: [String: Any], now: Date) throws -> GrokCredentials {
        let authMode = (record["auth_mode"] as? String)?.lowercased()
        if let authMode, authMode != "oidc" {
            throw GrokCLIAuthImporterError.unsupportedAuthMode
        }

        let issuerString = (record["oidc_issuer"] as? String) ?? GrokCredentials.expectedIssuer.absoluteString
        guard let issuer = URL(string: issuerString),
              issuer.host == GrokCredentials.expectedIssuer.host else {
            throw GrokCLIAuthImporterError.unsupportedIssuer
        }

        let clientID = (record["oidc_client_id"] as? String) ?? GrokCredentials.expectedClientID
        guard clientID == GrokCredentials.expectedClientID else {
            throw GrokCLIAuthImporterError.unsupportedClientID
        }

        let accessToken = ((record["key"] as? String) ?? (record["access_token"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let refreshToken = (record["refresh_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty, !refreshToken.isEmpty else {
            throw GrokCLIAuthImporterError.missingTokens
        }

        let expiresAt = parseExpiration(record["expires_at"]) ?? now.addingTimeInterval(6 * 3600)
        guard expiresAt.timeIntervalSince1970 > 0 else {
            throw GrokCLIAuthImporterError.invalidExpiration
        }

        let firstName = record["first_name"] as? String
        let lastName = record["last_name"] as? String
        let displayName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return GrokCredentials(
            schemaVersion: GrokCredentials.currentSchemaVersion,
            issuer: issuer,
            clientID: clientID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: expiresAt,
            tokenType: "Bearer",
            scopes: [],
            userID: record["user_id"] as? String,
            principalID: record["principal_id"] as? String,
            principalType: record["principal_type"] as? String,
            teamID: record["team_id"] as? String,
            email: record["email"] as? String,
            displayName: displayName.isEmpty ? nil : displayName,
            importedAt: now,
            refreshedAt: nil
        )
    }

    private static func parseExpiration(_ raw: Any?) -> Date? {
        if let string = raw as? String {
            return GrokUsageParser.parseDate(string)
        }
        if let number = raw as? Double {
            let seconds = number > 1_000_000_000_000 ? number / 1000 : number
            return Date(timeIntervalSince1970: seconds)
        }
        if let number = raw as? Int {
            return parseExpiration(Double(number))
        }
        return nil
    }
}
