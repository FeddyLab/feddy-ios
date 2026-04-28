import Foundation

/// Persists an `anonymous_token` per app install in `UserDefaults`. Used as
/// the fallback identifier whenever the host app has not yet called
/// `Feddy.identify(externalUserId:)`.
struct AnonymousTokenStore: @unchecked Sendable {
    static let storageKey = "app.feddy.anonymousToken"

    let defaults: UserDefaults
    let generator: @Sendable () -> String

    init(
        defaults: UserDefaults = .standard,
        generator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.defaults = defaults
        self.generator = generator
    }

    /// Returns the existing token, generating and persisting one if none
    /// exists yet. Safe to call repeatedly — the first caller wins.
    func tokenOrCreate() -> String {
        if let existing = defaults.string(forKey: Self.storageKey), !existing.isEmpty {
            return existing
        }
        let fresh = generator()
        defaults.set(fresh, forKey: Self.storageKey)
        return fresh
    }
}
