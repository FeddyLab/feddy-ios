import Foundation

/// Public domain types returned by the read-side `Feddy.fetch*` methods
/// and the `Feddy.upvote(...)` / `Feddy.addComment(...)` write methods.
///
/// Wire format mirrors `feddy-api`'s response shape — snake_case JSON
/// keys are mapped explicitly via `CodingKeys`, so we never rely on
/// `JSONDecoder`'s `.convertFromSnakeCase` strategy (which mangles
/// initialisms like `URL` and `ID`).

extension Feddy {
    /// The three publicly-visible roadmap statuses, used by
    /// ``RoadmapView`` as horizontal tabs and by `fetchRequests(status:...)`
    /// as a single-value filter. Backend rejects any other value as
    /// `invalid_query` so internal triage state never leaks.
    public enum RoadmapStatus: String, Sendable, CaseIterable {
        case planned
        case inProgress = "in_progress"
        case completed
    }

    /// A single roadmap item — what `getWorkspaceRequestDetail` returns
    /// in the dashboard, plus the `attachments[]` array. Returned by
    /// `fetchRequest(id:)`. Matches `GET /v1/requests/:id`.
    public struct FeedbackRequest: Sendable, Identifiable, Codable, Hashable {
        public let id: String
        public let title: String
        public let description: String
        public let requestType: String
        /// One of `pending` / `planned` / `in_progress` / `completed` /
        /// `reviewed` / `rejected` / `duplicate`. The list endpoint only
        /// returns the public-roadmap subset (`planned` / `in_progress`
        /// / `completed`); the detail endpoint applies the same filter
        /// so any non-public id 404s.
        public let status: String
        public let priority: String
        public let boardId: String
        /// Stable workspace-scoped key (e.g. `"features"` / `"bugs"`)
        /// usable as the input to `Feddy.fetchRequests(boardKey:...)`
        /// and to look up a display name in the host app's
        /// `[FeedbackBoard]` array.
        public let boardKey: String
        public let officialReply: String?
        public let voteCount: Int
        /// Whether the current end user has voted on this request.
        /// Computed server-side from `request_vote` joined on the
        /// `as_external_user_id` / `as_anonymous_token` query
        /// parameters that the SDK auto-supplies on every fetch.
        public let voted: Bool
        public let createdAt: Date
        public let attachments: [Attachment]

        public init(
            id: String,
            title: String,
            description: String,
            requestType: String,
            status: String,
            priority: String,
            boardId: String,
            boardKey: String,
            officialReply: String?,
            voteCount: Int,
            voted: Bool = false,
            createdAt: Date,
            attachments: [Attachment] = []
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.requestType = requestType
            self.status = status
            self.priority = priority
            self.boardId = boardId
            self.boardKey = boardKey
            self.officialReply = officialReply
            self.voteCount = voteCount
            self.voted = voted
            self.createdAt = createdAt
            self.attachments = attachments
        }

        enum CodingKeys: String, CodingKey {
            case id, title, description, status, priority, voted
            case requestType = "request_type"
            case boardId = "board_id"
            case boardKey = "board_key"
            case officialReply = "official_reply"
            case voteCount = "vote_count"
            case createdAt = "created_at"
            case attachments
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.title = try c.decode(String.self, forKey: .title)
            self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            self.requestType = try c.decodeIfPresent(String.self, forKey: .requestType) ?? "feature"
            self.status = try c.decode(String.self, forKey: .status)
            self.priority = try c.decodeIfPresent(String.self, forKey: .priority) ?? "medium"
            self.boardId = try c.decode(String.self, forKey: .boardId)
            self.boardKey = try c.decodeIfPresent(String.self, forKey: .boardKey) ?? ""
            self.officialReply = try c.decodeIfPresent(String.self, forKey: .officialReply)
            self.voteCount = try c.decodeIfPresent(Int.self, forKey: .voteCount) ?? 0
            self.voted = try c.decodeIfPresent(Bool.self, forKey: .voted) ?? false
            self.createdAt = try c.decode(Date.self, forKey: .createdAt)
            self.attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        }
    }

    /// One image attached to a `FeedbackRequest`. Public asset URL is
    /// resolved server-side (cdn.feddy.app on prod, Worker route on
    /// preview) so the SDK doesn't have to know about hosting topology.
    public struct Attachment: Sendable, Codable, Hashable {
        public let key: String
        public let assetURL: URL
        public let contentType: String
        public let size: Int

        public init(key: String, assetURL: URL, contentType: String, size: Int) {
            self.key = key
            self.assetURL = assetURL
            self.contentType = contentType
            self.size = size
        }

        enum CodingKeys: String, CodingKey {
            case key
            case assetURL = "asset_url"
            case contentType = "content_type"
            case size
        }
    }

    /// One page of `fetchRequests(...)`. Pass `nextCursor` back as the
    /// `cursor:` parameter on the next call to load more; nil means no
    /// further pages.
    public struct RequestList: Sendable, Codable {
        public let items: [FeedbackRequest]
        public let nextCursor: String?

        public init(items: [FeedbackRequest], nextCursor: String?) {
            self.items = items
            self.nextCursor = nextCursor
        }

        enum CodingKeys: String, CodingKey {
            case items
            case nextCursor = "next_cursor"
        }
    }

    /// One comment posted by an end user (or a dashboard operator, but
    /// internal-only operator comments are filtered server-side and
    /// never reach the SDK).
    public struct FeedbackComment: Sendable, Identifiable, Codable, Hashable {
        public let id: String
        public let content: String
        public let authorEndUserId: String?
        public let createdAt: Date
        public let updatedAt: Date

        public init(
            id: String,
            content: String,
            authorEndUserId: String?,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.content = content
            self.authorEndUserId = authorEndUserId
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        enum CodingKeys: String, CodingKey {
            case id, content
            case authorEndUserId = "author_end_user_id"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.content = try c.decode(String.self, forKey: .content)
            self.authorEndUserId = try c.decodeIfPresent(String.self, forKey: .authorEndUserId)
            self.createdAt = try c.decode(Date.self, forKey: .createdAt)
            // POST /v1/requests/:id/comments doesn't return updated_at on
            // the freshly-created row response; default to createdAt so
            // the SDK can still surface the row immediately.
            self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? self.createdAt
        }
    }

    /// One page of `fetchComments(...)`.
    public struct CommentList: Sendable, Codable {
        public let items: [FeedbackComment]
        public let nextCursor: String?

        public init(items: [FeedbackComment], nextCursor: String?) {
            self.items = items
            self.nextCursor = nextCursor
        }

        enum CodingKeys: String, CodingKey {
            case items
            case nextCursor = "next_cursor"
        }
    }

    /// Result of `Feddy.upvote(...)` — the toggled flag and the new
    /// total. Server is the source of truth here; the SDK does not
    /// cache vote state across sessions.
    public struct VoteState: Sendable, Codable, Hashable {
        public let voted: Bool
        public let voteCount: Int

        public init(voted: Bool, voteCount: Int) {
            self.voted = voted
            self.voteCount = voteCount
        }

        enum CodingKeys: String, CodingKey {
            case voted
            case voteCount = "vote_count"
        }
    }
}
