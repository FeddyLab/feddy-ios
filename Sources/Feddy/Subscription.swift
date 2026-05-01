import Foundation

extension Feddy {
    /// Snapshot of an end user's subscription state at a point in time.
    ///
    /// Mirrors the four columns the Feddy server records on
    /// `workspace_end_user`. Pass to ``Feddy/setSubscription(_:)`` to
    /// override automatic StoreKit 2 detection, e.g. when your app uses
    /// RevenueCat or another store-of-record:
    ///
    /// ```swift
    /// Feddy.setSubscription(
    ///     Feddy.Subscription(
    ///         isPaid: true,
    ///         status: .active,
    ///         productId: "com.foo.pro_monthly",
    ///         expiresAt: customerInfo.expirationDate
    ///     )
    /// )
    /// ```
    ///
    /// Pass `nil` to clear the manual override and fall back to
    /// automatic detection (when configure's `autoDetectSubscription`
    /// is true).
    public struct Subscription: Sendable, Equatable {
        public let isPaid: Bool
        public let status: Status
        public let productId: String?
        public let expiresAt: Date?

        public init(
            isPaid: Bool,
            status: Status,
            productId: String? = nil,
            expiresAt: Date? = nil
        ) {
            self.isPaid = isPaid
            self.status = status
            self.productId = productId
            self.expiresAt = expiresAt
        }

        /// Coarse subscription status. Maps 1:1 to the server's
        /// `subscription_status` text column.
        public enum Status: String, Sendable, Codable, Equatable {
            /// Active paid subscription.
            case active
            /// Introductory / promotional trial period.
            case trial
            /// Previously paid but now expired or revoked.
            case expired
            /// No subscription on file.
            case none
        }
    }
}
