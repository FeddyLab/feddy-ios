import Foundation

#if canImport(StoreKit)
import StoreKit

/// Reads the host app's current StoreKit 2 entitlements and derives a
/// `Feddy.Subscription` snapshot.
///
/// Strategy:
///
/// 1. Walk `Transaction.currentEntitlements` (verified transactions
///    only — failed verification is ignored, same as Apple's Sample
///    Code recommends).
/// 2. Derive a candidate `Subscription` per transaction.
/// 3. Reduce to the highest-priority candidate:
///    `active > trial > expired > none`. Apps with stacked
///    subscriptions (consumables on top of subs) commonly have
///    multiple entitlements; we surface the most "engaged" one.
///
/// `none` is returned when the user has never had any entitlement at
/// all — that's distinct from "had one and let it lapse" (which is
/// `expired` with the lapsed productId).
enum StoreKitDetector {
    @available(iOS 15.0, macOS 12.0, *)
    static func currentSubscription() async -> Feddy.Subscription {
        var best: Feddy.Subscription = .empty

        for await result in Transaction.currentEntitlements {
            // Drop failed verifications — Apple's docs say not to
            // grant entitlement on these. .verified delivers a
            // signed Transaction.
            guard case .verified(let transaction) = result else {
                continue
            }
            let candidate = derive(from: transaction)
            if candidate.priority > best.priority {
                best = candidate
            }
        }

        return best
    }

    @available(iOS 15.0, macOS 12.0, *)
    private static func derive(from transaction: Transaction) -> Feddy.Subscription {
        let now = Date()
        let isExpired: Bool = {
            if transaction.revocationDate != nil { return true }
            if let expiration = transaction.expirationDate, expiration <= now {
                return true
            }
            return false
        }()

        let isTrial = transaction.offerType == .introductory

        let status: Feddy.Subscription.Status = {
            if isExpired { return .expired }
            if isTrial { return .trial }
            return .active
        }()

        let isPaid: Bool = (status == .active || status == .trial)

        return Feddy.Subscription(
            isPaid: isPaid,
            status: status,
            productId: transaction.productID,
            expiresAt: transaction.expirationDate
        )
    }
}

extension Feddy.Subscription {
    fileprivate static let empty = Feddy.Subscription(
        isPaid: false,
        status: .none,
        productId: nil,
        expiresAt: nil
    )

    /// Internal ordering used to pick the most relevant entitlement
    /// when the host app has more than one. Higher = more engaged.
    fileprivate var priority: Int {
        switch status {
        case .active: return 3
        case .trial: return 2
        case .expired: return 1
        case .none: return 0
        }
    }
}

#else

// Non-Apple platforms (Linux CI / FoundationOnly): StoreKit isn't
// available, so the auto-detect path is a hard no-op. Manual
// `Feddy.setSubscription(...)` still works because it doesn't depend
// on StoreKit.
enum StoreKitDetector {
    @available(iOS 15.0, macOS 12.0, *)
    static func currentSubscription() async -> Feddy.Subscription {
        Feddy.Subscription(isPaid: false, status: .none)
    }
}

#endif
