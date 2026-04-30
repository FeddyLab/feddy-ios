import Foundation

/// Read-side + interactive write-side endpoints (list / detail /
/// comments / upvote / addComment). The fire-and-forget submitRequest
/// path lives in `SubmitRequest.swift`; this module covers everything
/// the host app needs the response from.

extension FeddyClient {
    @available(iOS 15.0, macOS 12.0, *)
    func fetchRequests(
        boardKey: String?,
        status: Feddy.RoadmapStatus?,
        limit: Int,
        cursor: String?
    ) async throws -> Feddy.RequestList {
        let clamped = max(1, min(limit, 100))
        return try await get(
            path: "/v1/requests",
            query: [
                "board_key": boardKey,
                "status": status?.rawValue,
                "limit": String(clamped),
                "cursor": cursor,
            ]
        )
    }

    @available(iOS 15.0, macOS 12.0, *)
    func fetchRequest(id: String) async throws -> Feddy.FeedbackRequest {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FeddyError.invalidPayload(reason: "Request id must not be empty")
        }
        let escaped = trimmed.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? trimmed
        return try await get(path: "/v1/requests/\(escaped)")
    }

    @available(iOS 15.0, macOS 12.0, *)
    func fetchComments(
        requestId: String,
        limit: Int,
        cursor: String?
    ) async throws -> Feddy.CommentList {
        let trimmed = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FeddyError.invalidPayload(reason: "Request id must not be empty")
        }
        let escaped = trimmed.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? trimmed
        let clamped = max(1, min(limit, 100))
        return try await get(
            path: "/v1/requests/\(escaped)/comments",
            query: [
                "limit": String(clamped),
                "cursor": cursor,
            ]
        )
    }

    @available(iOS 15.0, macOS 12.0, *)
    func toggleVote(requestId: String) async throws -> Feddy.VoteState {
        let trimmed = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FeddyError.invalidPayload(reason: "Request id must not be empty")
        }
        let escaped = trimmed.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? trimmed
        let body = VoteRequestBody(
            externalUserId: lastExternalUserId,
            anonymousToken: lastExternalUserId == nil ? anonymousToken : nil
        )
        return try await postReturning(
            path: "/v1/requests/\(escaped)/vote",
            body: body
        )
    }

    @available(iOS 15.0, macOS 12.0, *)
    func addComment(requestId: String, body: String) async throws -> Feddy.FeedbackComment {
        let trimmedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRequestId.isEmpty else {
            throw FeddyError.invalidPayload(reason: "Request id must not be empty")
        }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            throw FeddyError.invalidPayload(reason: "Comment body must not be empty")
        }
        let escaped = trimmedRequestId.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? trimmedRequestId
        let payload = AddCommentBody(
            externalUserId: lastExternalUserId,
            anonymousToken: lastExternalUserId == nil ? anonymousToken : nil,
            content: trimmedBody
        )
        return try await postReturning(
            path: "/v1/requests/\(escaped)/comments",
            body: payload
        )
    }
}

struct VoteRequestBody: Encodable {
    let externalUserId: String?
    let anonymousToken: String?

    enum CodingKeys: String, CodingKey {
        case externalUserId = "external_user_id"
        case anonymousToken = "anonymous_token"
    }
}

struct AddCommentBody: Encodable {
    let externalUserId: String?
    let anonymousToken: String?
    let content: String

    enum CodingKeys: String, CodingKey {
        case externalUserId = "external_user_id"
        case anonymousToken = "anonymous_token"
        case content
    }
}
