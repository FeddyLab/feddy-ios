import Foundation

/// A board to display in ``RequestComposeView``'s picker. The `key` is
/// what the SDK writes to `request.board_key` on submit; the `name` is
/// what the user sees.
///
/// For the workspace's default boards, use the convenience constants on
/// this type — they ship with the SDK's bundled localizations:
///
/// ```swift
/// RequestComposeView()  // [.featureRequest, .bugReport]
/// ```
///
/// For workspace-specific custom boards (anything you added via
/// `dashboard.feddy.app/w/<ws>/boards`), pass them explicitly. You're
/// responsible for the display name's localization — the SDK does not
/// know about your custom boards.
///
/// ```swift
/// RequestComposeView(boards: [
///     .featureRequest,
///     .bugReport,
///     .init(key: "discussions", name: "Discussions"),
/// ])
/// ```
public struct FeedbackBoard: Sendable, Hashable, Identifiable, Codable {
    /// Maps to `board.key` in the dashboard. Sent as `request.board_key`
    /// on submit.
    public let key: String

    /// Display label used in the picker. For SDK-shipped system keys
    /// (`features` / `bugs`) this is overridden by the bundled i18n
    /// catalog at render time; for custom keys this is whatever the
    /// admin typed in the dashboard (or the host explicitly passed).
    public let name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }

    public var id: String { key }
}

extension FeedbackBoard {
    /// Default board for feature requests / suggestions. Created
    /// automatically when a workspace is provisioned. The display name
    /// is pulled from the SDK's bundled localization catalog.
    public static var featureRequest: FeedbackBoard {
        FeedbackBoard(
            key: "features",
            name: Localization.string("feddy.compose.board.features")
        )
    }

    /// Default board for bug reports. Created automatically when a
    /// workspace is provisioned.
    public static var bugReport: FeedbackBoard {
        FeedbackBoard(
            key: "bugs",
            name: Localization.string("feddy.compose.board.bugs")
        )
    }

    /// The two system boards every Feddy workspace ships with.
    public static let systemDefaults: [FeedbackBoard] = [
        .featureRequest,
        .bugReport,
    ]
}

extension FeddyClient {
    @available(iOS 15.0, macOS 12.0, *)
    func submitRequest(
        title: String,
        description: String?,
        boardKey: String?
    ) async throws {
        let body = SubmitRequestBody(
            externalUserId: lastExternalUserId,
            anonymousToken: lastExternalUserId == nil ? anonymousToken : nil,
            title: title,
            description: description,
            boardKey: boardKey,
            attachmentKeys: nil
        )
        _ = try await postRaw(path: "/v1/requests", body: body)
    }

    /// Variant used by the public fire-and-forget entry point: handles
    /// console logging + offline-queue routing internally so the public
    /// surface stays a one-liner. Network errors / 5xx → enqueue. 4xx →
    /// logged but dropped (retrying bad payloads is a death loop). 2xx →
    /// drain any pending entries opportunistically.
    ///
    /// Attachments (`attachmentJPEGs`, already-compressed JPEG bytes)
    /// upload sequentially via ``uploadAttachment(jpeg:)`` before the
    /// final POST /v1/requests. Per-image upload is fault-tolerant:
    /// failures are logged and skipped, and the request still creates
    /// with whichever keys did succeed. Once a key is in R2 the offline
    /// queue can replay POST /v1/requests indefinitely without re-uploading.
    @available(iOS 15.0, macOS 12.0, *)
    func submitRequestFireAndForget(
        title: String,
        description: String?,
        boardKey: String?,
        attachmentJPEGs: [Data] = []
    ) async {
        var attachmentKeys: [String] = []
        for jpeg in attachmentJPEGs {
            do {
                let key = try await uploadAttachment(jpeg: jpeg)
                attachmentKeys.append(key)
            } catch {
                print("[Feddy] attachment upload failed — skipping: \(error.localizedDescription)")
            }
        }

        let body = SubmitRequestBody(
            externalUserId: lastExternalUserId,
            anonymousToken: lastExternalUserId == nil ? anonymousToken : nil,
            title: title,
            description: description,
            boardKey: boardKey,
            attachmentKeys: attachmentKeys.isEmpty ? nil : attachmentKeys
        )
        do {
            _ = try await postRaw(path: "/v1/requests", body: body)
            await replayQueue()
        } catch let error {
            handleSubmitFailure(path: "/v1/requests", body: body, error: error)
        }
    }

    /// Re-attempt every queued POST. Items that succeed are removed;
    /// items that hit another retryable error stay enqueued (with their
    /// `attempts` count bumped); items that hit a 4xx are dropped.
    @available(iOS 15.0, macOS 12.0, *)
    func replayQueue() async {
        let pending = requestQueue.snapshot
        guard !pending.isEmpty else { return }

        for item in pending {
            do {
                _ = try await postRawData(path: item.path, encodedBody: item.body)
                requestQueue.remove(id: item.id)
            } catch let error {
                if shouldRetry(error: error) {
                    bumpAttempts(itemId: item.id)
                } else {
                    print("[Feddy] dropping queued request \(item.id) — non-retryable error: \(error.localizedDescription)")
                    requestQueue.remove(id: item.id)
                }
            }
        }
    }

    // MARK: - Failure routing

    private func handleSubmitFailure<Body: Encodable>(
        path: String,
        body: Body,
        error: Error
    ) {
        if shouldRetry(error: error) {
            do {
                let encoded = try JSONEncoder.feddy.encode(body)
                requestQueue.enqueue(path: path, body: encoded)
                print("[Feddy] submitRequest queued for retry — \(error.localizedDescription)")
            } catch {
                print("[Feddy] submitRequest dropped — failed to encode body for queueing")
            }
        } else {
            print("[Feddy] submitRequest failed — \(error.localizedDescription)")
        }
    }

    private func shouldRetry(error: Error) -> Bool {
        switch error {
        case let feddyError as FeddyError:
            switch feddyError {
            case .network:
                return true
            case .http(let status, _, _):
                return status >= 500
            case .notConfigured, .invalidAPIKey, .invalidPayload, .decoding:
                return false
            }
        default:
            return false
        }
    }

    private func bumpAttempts(itemId: String) {
        var items = requestQueue.snapshot
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else {
            return
        }
        items[idx].attempts += 1
        requestQueue.replace(items)
    }
}

struct SubmitRequestBody: Encodable {
    let externalUserId: String?
    let anonymousToken: String?
    let title: String
    let description: String?
    let boardKey: String?
    let attachmentKeys: [String]?

    enum CodingKeys: String, CodingKey {
        case externalUserId = "external_user_id"
        case anonymousToken = "anonymous_token"
        case title
        case description
        case boardKey = "board_key"
        case attachmentKeys = "attachment_keys"
    }
}
