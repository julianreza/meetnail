/*
 * API Contract — Notulen Summary Webhook Integration
 * --------------------------------------------------
 * Default endpoint: https://antarracoding.web.id/relay/webhook/text
 * Can be overridden in Pengaturan -> Sistem -> Integrasi API Backend Notulen
 * (persisted via VoiceSettings and macOS Keychain `NotulenBackendKeychain`).
 *
 * Request:
 *   Method: POST
 *   Headers:
 *     Content-Type: application/json
 *     Accept: application/json
 *     Authorization / Custom Header according to `BackendAuthScheme`:
 *       - .none         -> (omitted, default)
 *       - .bearer       -> Authorization: Bearer <token>
 *       - .apiKeyHeader -> <customAuthHeaderName>: <token>
 *       - .basic        -> Authorization: Basic <base64(user:pass)>
 *
 * JSON Body (`NotulenSummarySubmissionPayload`):
 *   {
 *     "text": "## Ringkasan Rapat...",
 *     "title": "Sinkronisasi Mingguan Tim Engineering",
 *     "source": "zoom"
 *   }
 *
 * Expected Response (2xx JSON):
 *   Any 2xx status succeeds. If JSON is returned, `NotulenBackendClient.submit`
 *   flexibly extracts `id` / `summary_id` / `notulen_id` (top-level or under `data`)
 *   and `message` / `detail` into `NotulenSubmissionRecord`.
 */

import Foundation
import Security

enum BackendAuthScheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case bearer
    case apiKeyHeader
    case basic
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bearer: "Bearer Token"
        case .apiKeyHeader: "API Key Header"
        case .basic: "Basic Auth"
        case .none: "Tanpa Auth"
        }
    }

    var credentialPlaceholder: String {
        switch self {
        case .bearer: "Token Bearer (contoh: eyJhbGciOi...)"
        case .apiKeyHeader: "API Key rahasia"
        case .basic: "username:password atau token Base64"
        case .none: ""
        }
    }

    var requiresCredential: Bool {
        self != .none
    }
}

enum NotulenBackendKeychain {
    nonisolated static let service = "nail.backend.api"
    nonisolated static let account = "api-credential"

    @discardableResult
    nonisolated static func save(_ credential: String) -> Bool {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return false
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    nonisolated static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        let credential = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return credential.isEmpty ? nil : credential
    }

    @discardableResult
    nonisolated static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    nonisolated static func hasCredential() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

struct NotulenBackendConfig: Equatable, Sendable {
    var endpointURLString: String
    var authScheme: BackendAuthScheme
    var customAuthHeaderName: String
    var timeoutSeconds: TimeInterval = 30

    init(
        endpointURLString: String = NotulenBackendClient.defaultEndpointURLString,
        authScheme: BackendAuthScheme = .none,
        customAuthHeaderName: String = "X-API-Key",
        timeoutSeconds: TimeInterval = 30
    ) {
        self.endpointURLString = endpointURLString
        self.authScheme = authScheme
        self.customAuthHeaderName = customAuthHeaderName
        self.timeoutSeconds = timeoutSeconds
    }

    var resolvedEndpointURL: URL? {
        let trimmed = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return components.url
    }

    var isConfigured: Bool {
        resolvedEndpointURL != nil
    }
}

struct NotulenSummarySubmissionPayload: Codable, Equatable, Sendable {
    var text: String
    var title: String
    var source: String

    init(text: String, title: String, source: String) {
        self.text = text
        self.title = title
        self.source = source
    }

    init(summary: NotulenSummary, rawMarkdown: String, submittedAt: Date = Date()) {
        _ = submittedAt
        let rendered = summary.renderedMarkdown().trimmingCharacters(in: .whitespacesAndNewlines)
        let executive = summary.executiveSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedText: String
        if !rendered.isEmpty {
            resolvedText = rendered
        } else if !executive.isEmpty {
            resolvedText = executive
        } else {
            resolvedText = rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        self.init(
            text: resolvedText,
            title: summary.title,
            source: Self.inferSource(from: summary.meetingLink)
        )
    }

    nonisolated static func inferSource(from meetingLink: String?) -> String {
        let trimmed = meetingLink?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "nail" }

        let hostOrLink = (URL(string: trimmed)?.host ?? trimmed).lowercased()
        if hostOrLink.contains("zoom.us") || hostOrLink.contains("zoom") {
            return "zoom"
        }
        if hostOrLink.contains("meet.google.com") {
            return "google-meet"
        }
        if hostOrLink.contains("teams.microsoft.com")
            || hostOrLink.contains("teams.live.com")
            || hostOrLink.contains("teams.cloud.microsoft") {
            return "teams"
        }
        return "nail"
    }

    nonisolated func prettyPrintedJSON() -> String {
        let encoder = NotulenBackendClient.makeEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

struct NotulenSubmissionRecord: Codable, Equatable, Sendable {
    var statusCode: Int
    var remoteId: String?
    var message: String?
    var endpointURL: String
    var submittedAt: Date
    var responseBodyPreview: String?
}

enum NotulenBackendError: LocalizedError, Equatable, Sendable {
    case endpointNotConfigured
    case invalidEndpointURL(String)
    case missingCredential(BackendAuthScheme)
    case httpError(statusCode: Int, message: String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured:
            "Endpoint API backend belum diatur. Silakan isi URL endpoint di Pengaturan → Sistem."
        case let .invalidEndpointURL(raw):
            "URL endpoint backend tidak valid (\(raw)). Gunakan alamat http:// atau https:// yang lengkap."
        case let .missingCredential(scheme):
            "Kredensial untuk skema \(scheme.label) belum diisi di Keychain."
        case let .httpError(statusCode, message):
            message.isEmpty
                ? "Pengiriman ke backend gagal (HTTP \(statusCode))."
                : "Backend mengembalikan error HTTP \(statusCode): \(message)"
        case let .networkError(detail):
            detail.isEmpty
                ? "Gagal terhubung ke server backend."
                : "Gagal terhubung ke server backend: \(detail)"
        }
    }
}

enum NotulenBackendClient {
    nonisolated static let defaultEndpointURLString = "https://antarracoding.web.id/relay/webhook/text"

    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated static func buildRequest(
        payload: NotulenSummarySubmissionPayload,
        config: NotulenBackendConfig,
        credential: String?
    ) throws -> URLRequest {
        let trimmedEndpoint = config.endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            throw NotulenBackendError.endpointNotConfigured
        }
        guard let url = config.resolvedEndpointURL else {
            throw NotulenBackendError.invalidEndpointURL(trimmedEndpoint)
        }

        var request = URLRequest(url: url, timeoutInterval: max(5, config.timeoutSeconds))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedCredential = credential?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch config.authScheme {
        case .bearer:
            guard !trimmedCredential.isEmpty else {
                throw NotulenBackendError.missingCredential(.bearer)
            }
            request.setValue("Bearer \(trimmedCredential)", forHTTPHeaderField: "Authorization")

        case .apiKeyHeader:
            guard !trimmedCredential.isEmpty else {
                throw NotulenBackendError.missingCredential(.apiKeyHeader)
            }
            let trimmedHeader = config.customAuthHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let headerName = trimmedHeader.isEmpty ? "X-API-Key" : trimmedHeader
            request.setValue(trimmedCredential, forHTTPHeaderField: headerName)

        case .basic:
            guard !trimmedCredential.isEmpty else {
                throw NotulenBackendError.missingCredential(.basic)
            }
            let encodedToken: String
            if trimmedCredential.contains(":") {
                encodedToken = Data(trimmedCredential.utf8).base64EncodedString()
            } else if Data(base64Encoded: trimmedCredential) != nil {
                encodedToken = trimmedCredential
            } else {
                encodedToken = Data(trimmedCredential.utf8).base64EncodedString()
            }
            request.setValue("Basic \(encodedToken)", forHTTPHeaderField: "Authorization")

        case .none:
            break
        }

        let encoder = makeEncoder()
        request.httpBody = try encoder.encode(payload)
        return request
    }

    nonisolated static func submit(
        summary: NotulenSummary,
        rawMarkdown: String,
        config: NotulenBackendConfig,
        credential: String? = NotulenBackendKeychain.load(),
        session: URLSession = .shared
    ) async throws -> NotulenSubmissionRecord {
        let payload = NotulenSummarySubmissionPayload(summary: summary, rawMarkdown: rawMarkdown)
        let request = try buildRequest(payload: payload, config: config, credential: credential)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let backendError as NotulenBackendError {
            throw backendError
        } catch {
            throw NotulenBackendError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NotulenBackendError.networkError("Respons server bukan HTTP yang valid.")
        }

        let rawPreview = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyPreview: String? = rawPreview.isEmpty ? nil : String(rawPreview.prefix(500))
        let extracted = extractResponseFields(from: data)

        guard (200...299).contains(http.statusCode) else {
            let errMessage = extracted.errorMessage
                ?? extracted.message
                ?? bodyPreview
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NotulenBackendError.httpError(statusCode: http.statusCode, message: errMessage)
        }

        return NotulenSubmissionRecord(
            statusCode: http.statusCode,
            remoteId: extracted.remoteId,
            message: extracted.message,
            endpointURL: request.url?.absoluteString ?? config.endpointURLString,
            submittedAt: Date(),
            responseBodyPreview: bodyPreview
        )
    }

    private nonisolated static func extractResponseFields(
        from data: Data
    ) -> (remoteId: String?, message: String?, errorMessage: String?) {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil)
        }

        let nestedData = json["data"] as? [String: Any]
        let idKeys = ["id", "summary_id", "notulen_id"]

        var remoteId: String?
        for key in idKeys {
            if let value = stringValue(json[key]) {
                remoteId = value
                break
            }
        }
        if remoteId == nil, let nestedData {
            for key in idKeys {
                if let value = stringValue(nestedData[key]) {
                    remoteId = value
                    break
                }
            }
        }

        let message = stringValue(json["message"])
            ?? stringValue(nestedData?["message"])
            ?? stringValue(json["status"])

        let errorMessage = stringValue(json["error"])
            ?? stringValue(json["detail"])
            ?? stringValue(nestedData?["error"])
            ?? stringValue(nestedData?["detail"])

        return (remoteId, message, errorMessage)
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let str as String:
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return nil
            }
            return num.stringValue
        default:
            return nil
        }
    }
}
