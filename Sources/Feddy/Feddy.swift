import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Public namespace and entry point for the Feddy SDK.
///
/// Two calls cover the integration:
///
/// ```swift
/// // 1. Once at app launch:
/// Feddy.configure(apiKey: "fed_xxxxxxxxxxxx")
///
/// // 2. After your auth handler runs:
/// Feddy.identify(userId: user.id, email: user.email, displayName: user.name)
/// ```
///
/// Both methods are synchronous, never throw, and never block. Errors
/// (invalid keys, network failures) are logged and swallowed so they
/// can't crash the host app or back up the call site with `try` /
/// `await` boilerplate. In debug builds bad keys also trip an
/// `assertionFailure` so integration mistakes surface immediately.
public enum Feddy {
    private static let state = Locked<FeddyClient?>(nil)

    /// Configure the SDK once at app launch with your **Project ID**
    /// (`fed_xxxxxxxxxxxx`, copied from your Feddy dashboard). Safe to
    /// call from `@main App.init()` or
    /// `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// Invalid IDs (wrong prefix, empty, or a server `fed_sk_*` key)
    /// are rejected with a console log + debug-build assertion.
    /// Subsequent calls to `identify` / `submitRequest` will then
    /// silently no-op — same as if you never called `configure`.
    ///
    /// On success, any `submitRequest` payloads queued during a prior
    /// offline session replay in the background.
    ///
    /// - Parameters:
    ///   - apiKey: Your Project ID (`fed_xxxxxxxxxxxx`).
    ///   - autoDetectSubscription: When `true` (default), the SDK
    ///     reads `Transaction.currentEntitlements` once after configure
    ///     and again after each ``identify(userId:email:displayName:avatarURL:)``
    ///     so feedback rows in your dashboard carry up-to-date
    ///     subscription state. Set to `false` if your app uses
    ///     RevenueCat or another store-of-record — pass the result of
    ///     that source to ``setSubscription(_:)`` instead.
    public static func configure(
        apiKey: String,
        autoDetectSubscription: Bool = true
    ) {
        do {
            let configuration = try FeddyConfiguration(apiKey: apiKey)
            let client = FeddyClient(configuration: configuration)
            state.write { $0 = client }

            if #available(iOS 15.0, macOS 12.0, *) {
                Task {
                    await client.replayQueue()
                }
                if autoDetectSubscription {
                    Task {
                        let detected = await StoreKitDetector.currentSubscription()
                        client.subscriptionStore.setAutoDetected(detected)
                    }
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            print("[Feddy] configure failed — \(message)")
            assertionFailure("[Feddy] configure failed — \(message)")
        }
    }

    /// Identify the current end user. Call this from your auth
    /// handler (or wherever your app first knows who the user is)
    /// with whatever fields you already have. All fields are optional;
    /// when none are passed, the SDK falls back to a per-install
    /// anonymous token so writes still attribute correctly.
    ///
    /// Fire-and-forget: the network request runs in the background.
    /// Failures are logged to the console; the call site never
    /// throws or awaits.
    public static func identify(
        userId: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        avatarURL: URL? = nil
    ) {
        guard let client = state.read({ $0 }) else {
            print("[Feddy] identify called before configure — ignoring")
            return
        }
        // Network sync needs URLSession's async API (iOS 15+ / macOS 12+).
        // Older OSes get a silent no-op — same pattern UserJot uses for its
        // background metadata fetch — so the call site stays unconditional
        // while the package itself can still ship to iOS 15+ / macOS 10.15+.
        if #available(iOS 15.0, macOS 12.0, *) {
            Task {
                do {
                    try await client.identify(
                        externalUserId: userId,
                        email: email,
                        displayName: displayName,
                        avatarURL: avatarURL
                    )
                } catch {
                    print("[Feddy] identify failed — \(error.localizedDescription)")
                }
            }
        }
    }

    /// Override the subscription snapshot the SDK attaches to its
    /// next ``identify(userId:email:displayName:avatarURL:)``. Use
    /// when your app's source of truth for paid state is RevenueCat,
    /// Adapty, or your own server rather than StoreKit 2 directly:
    ///
    /// ```swift
    /// Purchases.shared.getCustomerInfo { info, _ in
    ///     guard let info else { return }
    ///     let isPro = info.entitlements["pro"]?.isActive == true
    ///     Feddy.setSubscription(
    ///         isPro
    ///             ? .init(isPaid: true, status: .active,
    ///                     productId: info.activeSubscriptions.first,
    ///                     expiresAt: info.expirationDate(forEntitlement: "pro"))
    ///             : .init(isPaid: false, status: .none)
    ///     )
    /// }
    /// ```
    ///
    /// Pass `nil` to clear the override and fall back to automatic
    /// StoreKit 2 detection (when `configure`'s `autoDetectSubscription`
    /// is true).
    ///
    /// Fire-and-forget: stored locally and uploaded with the next
    /// identify call.
    public static func setSubscription(_ subscription: Subscription?) {
        guard let client = state.read({ $0 }) else {
            print("[Feddy] setSubscription called before configure — ignoring")
            return
        }
        client.subscriptionStore.setManualOverride(subscription)
    }

    /// Re-read `Transaction.currentEntitlements` from StoreKit 2.
    /// Useful right after a successful in-app purchase or when your
    /// app comes back to the foreground, so the next identify call
    /// reflects the user's current paid state without restarting the
    /// app.
    ///
    /// No-op when ``configure(apiKey:autoDetectSubscription:)`` was
    /// called with `autoDetectSubscription: false` — the manual
    /// override path is the source of truth in that mode.
    ///
    /// Fire-and-forget: returns immediately; the StoreKit read runs
    /// in the background.
    public static func refreshSubscription() {
        guard let client = state.read({ $0 }) else {
            print("[Feddy] refreshSubscription called before configure — ignoring")
            return
        }
        if #available(iOS 15.0, macOS 12.0, *) {
            Task {
                let detected = await StoreKitDetector.currentSubscription()
                client.subscriptionStore.setAutoDetected(detected)
            }
        }
    }

    /// Submit a feedback / feature request / bug report on behalf of the
    /// current end user. Fire-and-forget: the network call runs in the
    /// background; failures are logged + persisted to a local retry queue
    /// so they replay automatically on the next ``configure(apiKey:)`` or
    /// the next successful submit.
    ///
    /// The SDK uses ``identify(userId:email:displayName:avatarURL:)``'s
    /// last `userId` if known, otherwise a per-install anonymous token —
    /// end users never need to "log in" to Feddy for this to work.
    ///
    /// - Parameters:
    ///   - title: Short summary shown as the row title in the dashboard.
    ///     Required; trimmed empty titles are rejected client-side.
    ///   - description: Longer body text. Optional; up to ~5000 chars
    ///     server-side.
    ///   - boardKey: Which dashboard board the request lands in. Use the
    ///     `key` of any board you can see in `dashboard.feddy.app/w/<ws>`
    ///     — for the default workspace those are `"features"` and
    ///     `"bugs"`. Server falls back to the workspace's primary board
    ///     when omitted.
    ///   - images: Optional images to attach (iOS only). Each is
    ///     compressed to JPEG ≤ 800KB and uploaded sequentially before
    ///     the request is created. Per-image failures are logged and
    ///     skipped — the request still creates with whichever uploads
    ///     succeeded. Up to 3 images per request; entry UI is gated on
    ///     workspace plan via the `attachments_enabled` flag from
    ///     `/v1/identify`.
    #if canImport(UIKit)
    public static func submitRequest(
        title: String,
        description: String? = nil,
        boardKey: String? = nil,
        images: [UIImage] = []
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            print("[Feddy] submitRequest ignored — title is empty")
            assertionFailure("[Feddy] submitRequest title must not be empty")
            return
        }

        guard let client = state.read({ $0 }) else {
            print("[Feddy] submitRequest called before configure — ignoring")
            return
        }

        let jpegs: [Data] = images.compactMap { image in
            guard let data = ImageCompression.compressJPEG(image) else {
                print("[Feddy] image compression failed — skipping one attachment")
                return nil
            }
            return data
        }

        if #available(iOS 15.0, macOS 12.0, *) {
            Task {
                await client.submitRequestFireAndForget(
                    title: trimmedTitle,
                    description: description,
                    boardKey: boardKey,
                    attachmentJPEGs: jpegs
                )
            }
        }
    }
    #else
    public static func submitRequest(
        title: String,
        description: String? = nil,
        boardKey: String? = nil
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            print("[Feddy] submitRequest ignored — title is empty")
            assertionFailure("[Feddy] submitRequest title must not be empty")
            return
        }

        guard let client = state.read({ $0 }) else {
            print("[Feddy] submitRequest called before configure — ignoring")
            return
        }

        if #available(iOS 15.0, macOS 12.0, *) {
            Task {
                await client.submitRequestFireAndForget(
                    title: trimmedTitle,
                    description: description,
                    boardKey: boardKey
                )
            }
        }
    }
    #endif

    /// Fetch one page of public-roadmap requests for this workspace.
    ///
    /// Pass the `nextCursor` from the previous page back as `cursor` to
    /// load more; nil means no more pages. Items are ordered newest-first
    /// (matches `GET /v1/requests`).
    ///
    /// - Parameters:
    ///   - boardKey: Restrict to one board (e.g. `"features"` /
    ///     `"bugs"`). Omit to span every active board in the workspace.
    ///   - status: Restrict to a single roadmap status — used by
    ///     ``RoadmapView`` to populate one tab. Omit to return the
    ///     full public-roadmap subset (planned + in_progress + completed
    ///     interleaved by recency).
    ///   - limit: Page size, 1...100. Defaults to 20 to match
    ///     ``RequestListView``'s rendering.
    ///   - cursor: Opaque cursor from a prior page's `nextCursor`.
    @available(iOS 15.0, macOS 12.0, *)
    public static func fetchRequests(
        boardKey: String? = nil,
        status: Feddy.RoadmapStatus? = nil,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> Feddy.RequestList {
        let client = try currentClient()
        return try await client.fetchRequests(
            boardKey: boardKey,
            status: status,
            limit: limit,
            cursor: cursor
        )
    }

    /// Fetch a single roadmap request by id.
    ///
    /// Returns 404 (`FeedbackError.http(status: 404, ...)`) for non-public
    /// statuses (`pending` / `reviewed` / `rejected` / `duplicate`) so
    /// internal triage state never leaks to end users via the SDK.
    @available(iOS 15.0, macOS 12.0, *)
    public static func fetchRequest(id: String) async throws -> Feddy.FeedbackRequest {
        let client = try currentClient()
        return try await client.fetchRequest(id: id)
    }

    /// Fetch comments on a roadmap request, oldest-first.
    ///
    /// Internal-only operator comments (`request_comment.is_internal`)
    /// are filtered server-side and never reach the SDK.
    @available(iOS 15.0, macOS 12.0, *)
    public static func fetchComments(
        requestId: String,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> Feddy.CommentList {
        let client = try currentClient()
        return try await client.fetchComments(
            requestId: requestId,
            limit: limit,
            cursor: cursor
        )
    }

    /// Toggle the current end user's vote on a roadmap request.
    ///
    /// Idempotent — calling twice in a row first creates the vote, then
    /// removes it. Returns the new state; the SDK does not cache vote
    /// state across sessions, so the host UI should rely on this
    /// response (and on subsequent `fetchRequest`/`fetchRequests`).
    ///
    /// Uses the last identified user when available, falls back to the
    /// per-install anonymous token so users who never identified can
    /// still vote.
    @available(iOS 15.0, macOS 12.0, *)
    public static func upvote(requestId: String) async throws -> Feddy.VoteState {
        let client = try currentClient()
        return try await client.toggleVote(requestId: requestId)
    }

    /// Append a comment to a roadmap request, authored by the current
    /// end user. Returns the persisted row so the host UI can append
    /// it to the visible thread.
    ///
    /// Empty / whitespace-only bodies throw
    /// ``FeddyError/invalidPayload(reason:)`` before any network call;
    /// server-side limit is 2000 chars after trim.
    @available(iOS 15.0, macOS 12.0, *)
    public static func addComment(
        requestId: String,
        body: String
    ) async throws -> Feddy.FeedbackComment {
        let client = try currentClient()
        return try await client.addComment(requestId: requestId, body: body)
    }

    /// Drops any previously configured client and forgets the last
    /// identified user. Useful for tests and for "log out" flows that
    /// should stop attributing writes to a known user.
    ///
    /// The offline retry queue is intentionally **not** cleared — pending
    /// payloads still replay against the next configured client (using
    /// whatever identity was attached at enqueue time, including the
    /// anonymous token).
    public static func reset() {
        if let client = state.read({ $0 }) {
            client.identityStore.setLastExternalUserId(nil)
            client.identityStore.setAttachmentsEnabled(false)
            client.subscriptionStore.clearAll()
        }
        state.write { $0 = nil }
    }

    static func currentClient() throws -> FeddyClient {
        guard let client = state.read({ $0 }) else {
            throw FeddyError.notConfigured
        }
        return client
    }

    /// Whether the configured workspace is on a paid plan that includes
    /// attachment uploads. Cached from the last `/v1/identify` response;
    /// `false` until identify confirms otherwise. Used by
    /// ``RequestComposeView`` to gate the PhotosPicker entry — entry UI
    /// is hidden for non-premium workspaces rather than showing it and
    /// having uploads rejected.
    static var attachmentsEnabled: Bool {
        state.read { $0?.identityStore.attachmentsEnabled ?? false }
    }
}
