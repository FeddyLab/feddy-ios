import Foundation

/// Public namespace and entry point for the Feddy SDK.
///
/// Two calls cover the integration:
///
/// ```swift
/// // 1. Once at app launch:
/// Feddy.configure(apiKey: "fed_pk_…")
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

    /// Configure the SDK once at app launch with your project's
    /// publishable key (`fed_pk_…`). Safe to call from
    /// `@main App.init()` or `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// Invalid keys (wrong prefix, empty, or `fed_sk_*`) are rejected
    /// with a console log + debug-build assertion. Subsequent calls
    /// to `identify` will then silently no-op — same as if you never
    /// called `configure`.
    public static func configure(apiKey: String) {
        do {
            let configuration = try FeddyConfiguration(apiKey: apiKey)
            let client = FeddyClient(configuration: configuration)
            state.write { $0 = client }
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

    /// Drops any previously configured client. Useful for tests and
    /// for "log out" flows that should stop attributing writes to a
    /// known user.
    public static func reset() {
        state.write { $0 = nil }
    }

    static func currentClient() throws -> FeddyClient {
        guard let client = state.read({ $0 }) else {
            throw FeddyError.notConfigured
        }
        return client
    }
}
