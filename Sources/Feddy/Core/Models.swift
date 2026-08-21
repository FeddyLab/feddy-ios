import Foundation

struct FeddyConfig: Decodable {
    struct Brand: Decodable {
        let name: String
        let color: String?
        let logoUrl: String?
    }

    struct Category: Decodable {
        let code: String
        let label: String
    }

    let brand: Brand
    let replySlaText: String?
    let categories: [Category]
}

struct ConversationSummary: Decodable, Identifiable {
    let id: String
    let subject: String?
    let status: String
    let lastSeq: Int
    let lastMessageAt: Date
    var seenSeq: Int

    var hasUnread: Bool { lastSeq > seenSeq }
}

struct ConversationList: Decodable {
    let conversations: [ConversationSummary]
}

struct Part: Decodable, Identifiable {
    let seq: Int
    let authorType: String
    let body: String
    let createdAt: Date
    let authorName: String?
    let authorAvatarUrl: String?

    var id: Int { seq }
    var isFromContact: Bool { authorType == "contact" }

    /// Consecutive messages by the same author render as one visual run
    /// (avatar and name shown once).
    var authorRunKey: String { "\(authorType):\(authorName ?? "")" }
}

struct ConversationDetail: Decodable {
    let id: String
    let status: String
    let subject: String?
    let lastSeq: Int
    let parts: [Part]
}

struct CreatedConversation: Decodable {
    let id: String
    let status: String
    let lastSeq: Int
}

struct AppendedPart: Decodable {
    let conversationId: String
    let seq: Int
    let status: String
    let renewedFrom: String?
}

struct UnreadCount: Decodable {
    let unreadCount: Int
}

struct OkResponse: Decodable {
    let ok: Bool
}

struct IdentifyResponse: Decodable {
    let id: String
}

enum FeddyDecoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = withFractional.date(from: value) ?? plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognized date: \(value)"
                )
            )
        }
        return decoder
    }
}
