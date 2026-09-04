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

        /// What the chip actually shows. See `Strings.builtInCategoryLabel`.
        var displayLabel: String {
            Strings.builtInCategoryLabel(code) ?? label
        }
    }

    let brand: Brand
    let replySlaText: String?
    let categories: [Category]
    /// Whether the project can email replies (it has a verified sending
    /// domain). Optional so a server that predates the field decodes; see
    /// `emailCaptureEnabled` for the default.
    let emailCapture: Bool?

    /// False hides every email ask: a project that cannot mail replies must
    /// not collect addresses it will never write to. Absent means true.
    var emailCaptureEnabled: Bool { emailCapture ?? true }

    /// Mirrors the topics every project is seeded with. A topic is
    /// required, so the form needs something to offer even when the
    /// config fetch failed; unknown codes are ignored server-side, and
    /// these four resolve for any project that has not replaced them.
    static let fallbackCategories = [
        Category(code: "bug", label: "Bug"),
        Category(code: "feature", label: "Feature request"),
        Category(code: "question", label: "Question"),
        Category(code: "other", label: "Other"),
    ]
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

/// An image on a message. `url` is an API path rather than a picture:
/// fetching it proves this contact owns the attachment and returns a URL
/// that is good for a minute.
struct Attachment: Decodable, Identifiable {
    let id: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let url: String
}

/// What the client reports about a file it has already put in the bucket.
/// The key is a claim the server re-checks against the project.
struct UploadedAttachment {
    let key: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int

    var payload: [String: Any] {
        ["key": key, "filename": filename, "mime_type": mimeType, "size_bytes": sizeBytes]
    }
}

struct UploadSlot: Decodable {
    let key: String
    let uploadUrl: String
}

struct AttachmentURL: Decodable {
    let url: String
    let expiresIn: Int
}

struct Part: Decodable, Identifiable {
    let seq: Int
    let authorType: String
    let body: String
    let createdAt: Date
    let authorName: String?
    let authorAvatarUrl: String?
    let attachments: [Attachment]?
    /// Auto-replies only: "helpful", "not_helpful", or nil until the user
    /// answers. Mutable so a rating shows at once, before the next poll.
    var botFeedback: String?

    var id: Int { seq }
    var isFromContact: Bool { authorType == "contact" }
    var isFromBot: Bool { authorType == "bot" }

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

struct BotFeedbackResponse: Decodable {
    let ok: Bool
    /// "closed" after a helpful vote: the user resolved the thread.
    let status: String
    /// Set when a "no" was answered with the fallback message: the seq of
    /// that new bot message, worth fetching right away.
    let replySeq: Int?
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
