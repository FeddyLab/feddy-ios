import Foundation

/// Funnel telemetry for Smart Review. Four wire stages match the
/// server schema (`feddy-api/src/ingest/review-prompt-events.ts`):
///
/// - `shown` — sheet first appears (no rating yet).
/// - `rated` — user picks a star (1...5). Carries the rating.
/// - `routed_store` — user picked ≥4 and was forwarded to
///   `SKStoreReviewController`. Carries the rating.
/// - `routed_feedback` — user picked ≤3 and was forwarded to
///   ``RequestComposeView`` for private capture. Carries the rating.
///
/// Fire-and-forget: any network or encoding failure is logged and
/// dropped. Funnel telemetry must never affect the user's prompt
/// experience (no retries, no offline queue, no thrown errors).
enum ReviewPromptEventStage: String {
    case shown
    case rated
    case routedStore = "routed_store"
    case routedFeedback = "routed_feedback"
}

enum ReviewPromptEventLogger {
    @available(iOS 15.0, macOS 12.0, *)
    static func log(
        stage: ReviewPromptEventStage,
        rating: Int? = nil,
        trigger: String? = nil,
        client: FeddyClient
    ) {
        let body = EventBody(
            externalUserId: client.lastExternalUserId,
            anonymousToken:
                client.lastExternalUserId == nil ? client.anonymousToken : nil,
            stage: stage.rawValue,
            rating: rating,
            trigger: trigger
        )
        Task {
            do {
                _ = try await client.postRaw(
                    path: "/v1/review-prompt-events",
                    body: body
                )
            } catch {
                print(
                    "[Feddy] Smart Review event '\(stage.rawValue)' upload failed — \(error.localizedDescription)"
                )
            }
        }
    }
}

private struct EventBody: Encodable {
    let externalUserId: String?
    let anonymousToken: String?
    let stage: String
    let rating: Int?
    let trigger: String?

    enum CodingKeys: String, CodingKey {
        case externalUserId = "external_user_id"
        case anonymousToken = "anonymous_token"
        case stage
        case rating
        case trigger
    }
}
