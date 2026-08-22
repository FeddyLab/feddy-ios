import Foundation

struct APIError: Error {
    let status: Int
    let message: String

    var isRateLimited: Bool { status == 429 }
}

/// Thin async wrapper over the Feddy v1 HTTP API. Request bodies go
/// through JSONSerialization because identify() carries heterogeneous
/// attribute values; responses decode via Codable.
final class APIClient: @unchecked Sendable {
    private let projectId: String
    private let baseURL: URL
    private let anonId: String
    private let session: URLSession
    private let decoder = FeddyDecoding.decoder()

    init(projectId: String, baseURL: URL, anonId: String, session: URLSession = .shared) {
        self.projectId = projectId
        self.baseURL = baseURL
        self.anonId = anonId
        self.session = session
    }

    // MARK: - Endpoints

    func config() async throws -> FeddyConfig {
        try await request("v1/config")
    }

    func identify(
        externalId: String,
        email: String?,
        name: String?,
        attributes: [String: Any]
    ) async throws -> IdentifyResponse {
        var body: [String: Any] = [
            "external_id": externalId,
            "locale": Locale.preferredLanguages.first ?? Locale.current.identifier,
            "attributes": Self.sanitizeAttributes(attributes),
        ]
        if let email { body["email"] = email }
        if let name { body["name"] = name }
        return try await request("v1/contacts/identify", method: "POST", body: body)
    }

    func setEmail(_ email: String) async throws -> OkResponse {
        try await request("v1/contacts/email", method: "POST", body: ["email": email])
    }

    func conversations() async throws -> ConversationList {
        try await request("v1/conversations")
    }

    func conversation(id: String, sinceSeq: Int = 0) async throws -> ConversationDetail {
        let suffix = sinceSeq > 0 ? "?since_seq=\(sinceSeq)" : ""
        return try await request("v1/conversations/\(id)\(suffix)")
    }

    func createConversation(
        body text: String,
        categoryCode: String?,
        idempotencyKey: String
    ) async throws -> CreatedConversation {
        var body: [String: Any] = [
            "body": text,
            "platform": "ios",
            "context": DeviceContext.build(),
        ]
        if let categoryCode { body["category_code"] = categoryCode }
        return try await request(
            "v1/conversations", method: "POST", body: body, idempotencyKey: idempotencyKey
        )
    }

    func appendPart(
        conversationId: String,
        body text: String,
        idempotencyKey: String
    ) async throws -> AppendedPart {
        let body: [String: Any] = [
            "body": text,
            "platform": "ios",
            "context": DeviceContext.build(),
        ]
        return try await request(
            "v1/conversations/\(conversationId)/parts",
            method: "POST", body: body, idempotencyKey: idempotencyKey
        )
    }

    func markRead(conversationId: String, seenSeq: Int) async throws -> OkResponse {
        try await request(
            "v1/conversations/\(conversationId)/read",
            method: "POST", body: ["seen_seq": seenSeq]
        )
    }

    func unreadCount() async throws -> UnreadCount {
        try await request("v1/unread_count")
    }

    // MARK: - Transport

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        idempotencyKey: String? = nil
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError(status: 0, message: "invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(projectId)", forHTTPHeaderField: "Authorization")
        request.setValue(anonId, forHTTPHeaderField: "X-Feddy-Anon-Id")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = payload?["error"] as? String ?? "request failed (\(status))"
            throw APIError(status: status, message: message)
        }
        return try decoder.decode(T.self, from: data)
    }

    /// Keeps only JSON-representable scalar values; Date becomes an
    /// ISO 8601 string. Anything else is dropped client-side (the server
    /// silently drops out-of-contract values as well).
    static func sanitizeAttributes(_ attributes: [String: Any]) -> [String: Any] {
        var sanitized: [String: Any] = [:]
        let iso = ISO8601DateFormatter()
        for (key, value) in attributes {
            switch value {
            case let string as String:
                sanitized[key] = string
            case let bool as Bool:
                sanitized[key] = bool
            case let number as NSNumber:
                sanitized[key] = number
            case let date as Date:
                sanitized[key] = iso.string(from: date)
            default:
                continue
            }
        }
        return sanitized
    }
}
