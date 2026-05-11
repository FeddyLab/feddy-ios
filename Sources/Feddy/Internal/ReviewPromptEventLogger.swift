import Foundation

/// Funnel telemetry for Smart Review. Wire stages match the server
/// schema (`feddy-api/src/ingest/review-prompt-events.ts`):
///
/// - `shown` — sheet first appears (no choice yet).
/// - `liked` — user picked "like" in step 1.
/// - `disliked` — user picked "not really" in step 1.
/// - `routed_store` — user confirmed in step 2 and
///   `SKStoreReviewController` was invoked.
/// - `routed_feedback` — user picked "not really" and was forwarded
///   to ``RequestComposeView`` for private capture.
/// - `dismissed_store_confirm` — user reached step 2 then declined
///   ("Not now" or drag-away).
/// - `dismissed` — user closed the sheet on step 1 without choosing.
///
/// Fire-and-forget: any network or encoding failure is logged and
/// dropped. Funnel telemetry must never affect the user's prompt
/// experience (no retries, no offline queue, no thrown errors).
enum ReviewPromptEventStage: String {
    case shown
    case liked
    case disliked
    case routedStore = "routed_store"
    case routedFeedback = "routed_feedback"
    case dismissedStoreConfirm = "dismissed_store_confirm"
    case dismissed
}

enum ReviewPromptEventLogger {
    @available(iOS 15.0, macOS 12.0, *)
    static func log(
        stage: ReviewPromptEventStage,
        trigger: String? = nil,
        client: FeddyClient
    ) {
        let body = EventBody(
            externalUserId: client.lastExternalUserId,
            anonymousToken:
                client.lastExternalUserId == nil ? client.anonymousToken : nil,
            stage: stage.rawValue,
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
    let trigger: String?

    enum CodingKeys: String, CodingKey {
        case externalUserId = "external_user_id"
        case anonymousToken = "anonymous_token"
        case stage
        case trigger
    }
}
