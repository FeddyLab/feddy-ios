import Foundation

/// Persists per-install identity in `UserDefaults`:
///
/// - `anonymousToken`: a stable token used as the fallback identifier
///   whenever the host app has not (yet) called `Feddy.identify(...)`.
///   Generated lazily on first read, then immutable for the install life.
///
/// - `lastExternalUserId`: the `userId` most recently passed to
///   `Feddy.identify(...)`. Persisted so writes that happen after a
///   process restart (e.g. an offline-queued submitRequest replay) still
///   attribute to the right end user without requiring the host app to
///   call `identify` again first.
///
/// Anonymous and identified writes are not mutually exclusive —
/// `submitRequest` always picks `lastExternalUserId` if present and falls
/// back to `anonymousToken` otherwise. End users never need to "log in"
/// to Feddy for the SDK to work; the anonymous path is a first-class
/// citizen.
struct IdentityStore: @unchecked Sendable {
    static let anonymousTokenKey = "app.feddy.anonymousToken"
    static let lastExternalUserIdKey = "app.feddy.lastExternalUserId"
    static let attachmentsEnabledKey = "app.feddy.attachmentsEnabled"

    let defaults: UserDefaults
    let generator: @Sendable () -> String

    init(
        defaults: UserDefaults = .standard,
        generator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.defaults = defaults
        self.generator = generator
    }

    /// Returns the existing anonymous token, generating and persisting one
    /// if none exists yet. Safe to call repeatedly — the first caller wins.
    func tokenOrCreate() -> String {
        if let existing = defaults.string(forKey: Self.anonymousTokenKey),
           !existing.isEmpty {
            return existing
        }
        let fresh = generator()
        defaults.set(fresh, forKey: Self.anonymousTokenKey)
        return fresh
    }

    /// The most recent `userId` passed to `Feddy.identify(...)`, if any.
    /// `nil` means the SDK should fall back to `tokenOrCreate()`.
    var lastExternalUserId: String? {
        let value = defaults.string(forKey: Self.lastExternalUserIdKey)
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Persists `userId` so subsequent writes (and queued replays after a
    /// restart) carry the right identity. Pass `nil` from `Feddy.reset()`
    /// to forget.
    func setLastExternalUserId(_ value: String?) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: Self.lastExternalUserIdKey)
        } else {
            defaults.removeObject(forKey: Self.lastExternalUserIdKey)
        }
    }

    /// Cached premium gate from the last successful `/v1/identify` call.
    /// `false` until identify confirms otherwise — we hide attachment UI
    /// rather than show it speculatively and have uploads rejected.
    var attachmentsEnabled: Bool {
        defaults.bool(forKey: Self.attachmentsEnabledKey)
    }

    func setAttachmentsEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.attachmentsEnabledKey)
    }
}
