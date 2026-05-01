import Foundation

/// Two-layer state for subscription tracking:
///
/// - `manualOverride` — set by `Feddy.setSubscription(_:)`. Persisted
///   across launches via UserDefaults so a host app that calls it
///   once after RevenueCat init keeps the override even after the
///   process restarts. `nil` means "no manual override; use auto".
///
/// - `autoDetected` — set by ``StoreKitDetector`` reading
///   `Transaction.currentEntitlements`. Re-derived on every launch /
///   `refreshSubscription()` call, so we deliberately don't persist
///   it (StoreKit is the source of truth for the auto path).
///
/// `effective` resolves manual > auto. Returns nil when neither is
/// set — `Feddy.identify(...)` then omits the `subscription` key from
/// the request body, leaving the server's four columns untouched.
struct SubscriptionStore: @unchecked Sendable {
    static let manualOverrideKey = "app.feddy.subscription.manual"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Manual override (persisted)

    var manualOverride: Feddy.Subscription? {
        guard let data = defaults.data(forKey: Self.manualOverrideKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedSubscription.self, from: data)
            .toPublic()
    }

    func setManualOverride(_ subscription: Feddy.Subscription?) {
        guard let subscription else {
            defaults.removeObject(forKey: Self.manualOverrideKey)
            return
        }
        let persisted = PersistedSubscription(from: subscription)
        if let data = try? JSONEncoder().encode(persisted) {
            defaults.set(data, forKey: Self.manualOverrideKey)
        }
    }

    // MARK: - Auto detected (in-memory)

    private static let autoDetectedLock = NSLock()
    private static var autoDetected: Feddy.Subscription?

    var autoDetected: Feddy.Subscription? {
        Self.autoDetectedLock.lock()
        defer { Self.autoDetectedLock.unlock() }
        return Self.autoDetected
    }

    func setAutoDetected(_ subscription: Feddy.Subscription?) {
        Self.autoDetectedLock.lock()
        Self.autoDetected = subscription
        Self.autoDetectedLock.unlock()
    }

    // MARK: - Effective

    /// Resolves manual > auto. `nil` = the SDK has no opinion; identify
    /// will omit `subscription` from the request body and the server's
    /// four columns stay at whatever value they already had.
    var effective: Feddy.Subscription? {
        manualOverride ?? autoDetected
    }

    /// Clear both layers — used by `Feddy.reset()`.
    func clearAll() {
        defaults.removeObject(forKey: Self.manualOverrideKey)
        setAutoDetected(nil)
    }
}

/// JSON-encodable copy used only for UserDefaults persistence. Keeps
/// the public `Feddy.Subscription` free from Codable conformance noise
/// (and lets us evolve persistence without breaking the public type).
private struct PersistedSubscription: Codable {
    let isPaid: Bool
    let status: String
    let productId: String?
    let expiresAt: Date?

    init(from subscription: Feddy.Subscription) {
        self.isPaid = subscription.isPaid
        self.status = subscription.status.rawValue
        self.productId = subscription.productId
        self.expiresAt = subscription.expiresAt
    }

    func toPublic() -> Feddy.Subscription? {
        guard let status = Feddy.Subscription.Status(rawValue: status) else {
            return nil
        }
        return Feddy.Subscription(
            isPaid: isPaid,
            status: status,
            productId: productId,
            expiresAt: expiresAt
        )
    }
}
