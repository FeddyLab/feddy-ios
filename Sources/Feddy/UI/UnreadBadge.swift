#if canImport(UIKit)
import SwiftUI

public extension View {
    /// Marks a list row with the number of unread replies, using the
    /// system's own badge — the one that sits on rows in Settings — and
    /// keeps it current. Nothing is drawn while nothing is unread.
    ///
    /// ```swift
    /// Button(action: { Feddy.present() }) { Text("Support") }
    ///     .feddyUnreadBadge()
    /// ```
    ///
    /// Badges are rendered by `List`, `Form`, and `TabView`; anywhere else
    /// the modifier is inert, so observe ``FeddyUnread`` and draw your own.
    func feddyUnreadBadge() -> some View {
        modifier(FeddyUnreadBadgeModifier())
    }
}

private struct FeddyUnreadBadgeModifier: ViewModifier {
    @ObservedObject private var unread = FeddyUnread.shared

    func body(content: Content) -> some View {
        // A zero badge renders nothing, so there is no branch to write.
        content.badge(unread.count)
    }
}
#endif
