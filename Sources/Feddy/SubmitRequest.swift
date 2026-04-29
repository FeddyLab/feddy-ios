import Foundation

extension Feddy {
    /// Common values for the `type` parameter of ``Feddy/submitRequest(title:description:type:)``.
    ///
    /// `type` is a free-form lowercase tag (server-side regex
    /// `^[a-z][a-z0-9_]{0,31}$`) used purely as a grouping hint in the
    /// dashboard. These constants cover the three cases most apps need;
    /// callers can pass any conforming string for product-specific tags
    /// (e.g. `"pricing"`, `"onboarding"`).
    public enum RequestType {
        public static let feature = "feature"
        public static let bug = "bug"
        public static let other = "other"
    }
}

extension FeddyClient {
    @available(iOS 15.0, macOS 12.0, *)
    func submitRequest(
        title: String,
        description: String?,
        type: String?
    ) async throws {
        let body = SubmitRequestBody(
            externalUserId: lastExternalUserId,
            anonymousToken: lastExternalUserId == nil ? anonymousToken : nil,
            title: title,
            description: description,
            requestType: type
        )
        _ = try await postRaw(path: "/v1/requests", body: body)
    }

    /// Variant used by the public fire-and-forget entry point: handles
    /// console logging + offline-queue routing internally so the public
    /// surface stays a one-liner. Network errors / 5xx → enqueue. 4xx →
    /// logged but dropped (retrying bad payloads is a death loop). 2xx →
    /// drain any pending entries opportunistically.
    @available(iOS 15.0, macOS 12.0, *)
    func submitRequestFireAndForget(
        title: String,
        description: String?,
        type: String?
    ) async {
        let body = SubmitRequestBody(
            externalUserId: lastExternalUserId,
            anonymousToken: lastExternalUserId == nil ? anonymousToken : nil,
            title: title,
            description: description,
            requestType: type
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
    let requestType: String?

    enum CodingKeys: String, CodingKey {
        case externalUserId = "external_user_id"
        case anonymousToken = "anonymous_token"
        case title
        case description
        case requestType = "request_type"
    }
}
