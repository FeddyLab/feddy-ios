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
        attachments: [UploadedAttachment] = [],
        idempotencyKey: String
    ) async throws -> CreatedConversation {
        var body: [String: Any] = [
            "body": text,
            "platform": "ios",
            "context": DeviceContext.build(),
            "attachments": attachments.map(\.payload),
        ]
        if let categoryCode { body["category_code"] = categoryCode }
        return try await request(
            "v1/conversations", method: "POST", body: body, idempotencyKey: idempotencyKey
        )
    }

    func appendPart(
        conversationId: String,
        body text: String,
        attachments: [UploadedAttachment] = [],
        idempotencyKey: String
    ) async throws -> AppendedPart {
        let body: [String: Any] = [
            "body": text,
            "platform": "ios",
            "context": DeviceContext.build(),
            "attachments": attachments.map(\.payload),
        ]
        return try await request(
            "v1/conversations/\(conversationId)/parts",
            method: "POST", body: body, idempotencyKey: idempotencyKey
        )
    }

    /// "Was this helpful?" on an auto-reply. One answer per bot message;
    /// a yes closes the conversation server-side.
    func sendBotFeedback(
        conversationId: String,
        seq: Int,
        helpful: Bool
    ) async throws -> BotFeedbackResponse {
        try await request(
            "v1/conversations/\(conversationId)/bot_feedback",
            method: "POST", body: ["seq": seq, "helpful": helpful]
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

    /// Permission to write one object, of one type, for one hour. The
    /// bucket credential never leaves the server.
    func createUpload(filename: String, mimeType: String, sizeBytes: Int) async throws -> UploadSlot {
        try await request(
            "v1/uploads",
            method: "POST",
            body: ["filename": filename, "mime_type": mimeType, "size_bytes": sizeBytes]
        )
    }

    /// A signed URL good for a minute, issued only after this contact is
    /// shown to own the attachment. Asked for when the image is displayed,
    /// not when the thread is loaded.
    func attachmentURL(id: String) async throws -> AttachmentURL {
        try await request("v1/attachments/\(id)")
    }

    /// Puts the bytes straight into the bucket with the signed URL. Not
    /// through `request`: this one talks to R2, not to Feddy, and carries
    /// none of our headers.
    func upload(data: Data, to urlString: String, mimeType: String) async throws {
        guard let url = URL(string: urlString) else {
            throw APIError(status: 0, message: "invalid upload URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, message: "upload failed")
        }
    }

    // MARK: - Transport

    /// The same value DeviceContext reports, so the server sees one
    /// language per device rather than two that could disagree.
    static var preferredLocale: String {
        Locale.preferredLanguages.first ?? Locale.current.identifier
    }

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
        // The language developer-written text comes back in (topic names,
        // the reply promise, auto-replies); the API translates server-side
        // and falls back to the default text for anything it lacks.
        request.setValue(Self.preferredLocale, forHTTPHeaderField: "X-Feddy-Locale")
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
