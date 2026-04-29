import Foundation

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
    public static func configure(apiKey: String) {
        do {
            let configuration = try FeddyConfiguration(apiKey: apiKey)
            let client = FeddyClient(configuration: configuration)
            state.write { $0 = client }

            if #available(iOS 15.0, macOS 12.0, *) {
                Task {
                    await client.replayQueue()
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
        avatarURL: URL? = nil,
        profile: [String: ProfileValue]? = nil
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
                        avatarURL: avatarURL,
                        profile: profile
                    )
                } catch {
                    print("[Feddy] identify failed — \(error.localizedDescription)")
                }
            }
        }
    }

    /// Submit a feedback / feature request / bug report on behalf of the
    /// current end user. Fire-and-forget: the network call runs in the
    /// background; failures are logged + persisted to a local retry queue
    /// so they replay automatically on the next ``configure(apiKey:)`` or
    /// the next successful submit.
    ///
    /// The SDK uses ``identify(userId:email:displayName:avatarURL:profile:)``'s
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
        }
        state.write { $0 = nil }
    }

    static func currentClient() throws -> FeddyClient {
        guard let client = state.read({ $0 }) else {
            throw FeddyError.notConfigured
        }
        return client
    }
}
