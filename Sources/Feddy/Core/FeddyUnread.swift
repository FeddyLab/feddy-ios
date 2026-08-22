import Combine
import Foundation

/// The unread reply count, published for SwiftUI.
///
/// Bridging `Feddy.onUnreadCountChanged` into an app's own observable
/// object is easy to get subtly wrong — a nested `ObservableObject` does
/// not propagate through an `@EnvironmentObject` container, so the count
/// updates while the view never redraws — so the SDK publishes it
/// directly. Prefer `.feddyUnreadBadge()`; observe this when the badge
/// needs to live somewhere a list badge cannot go.
///
/// ```swift
/// @ObservedObject private var unread = FeddyUnread.shared
/// ```
@MainActor
public final class FeddyUnread: ObservableObject {
    public static let shared = FeddyUnread()

    /// Replies the user has not opened yet; zero when everything is read.
    @Published public private(set) var count = 0

    private init() {}

    func update(_ value: Int) {
        guard count != value else { return }
        count = value
    }
}
