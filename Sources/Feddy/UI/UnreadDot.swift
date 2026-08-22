#if canImport(UIKit)
import SwiftUI

/// The unread count as the red marker iOS puts on rows that need
/// attention — the shape Settings uses beside "General" when an update is
/// waiting. Renders nothing at all while there is nothing unread, so it
/// can sit in a row unconditionally.
///
/// Place it wherever the row wants it, which is what makes it the right
/// tool for rows that draw their own chevron — those cannot use
/// ``SwiftUI/View/feddyUnreadBadge()``, since a list badge is pinned to
/// the trailing edge and would land outside the chevron.
///
/// ```swift
/// HStack {
///     Text("Support")
///     Spacer()
///     FeddyUnreadDot()
///     Image(systemName: "chevron.forward")
/// }
/// ```
public struct FeddyUnreadDot: View {
    @ObservedObject private var unread = FeddyUnread.shared

    private let showsCount: Bool

    /// - Parameter showsCount: draw the number inside the marker. A plain
    ///   dot when false, which suits a row that only needs to say "new".
    public init(showsCount: Bool = false) {
        self.showsCount = showsCount
    }

    public var body: some View {
        if unread.count > 0 {
            if showsCount {
                Text("\(unread.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemRed))
                    .clipShape(Capsule())
                    .accessibilityLabel(Text(Strings.newReply))
                    .accessibilityValue(Text("\(unread.count)"))
            } else {
                Circle()
                    .fill(Color(.systemRed))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(Text(Strings.newReply))
            }
        }
    }
}
#endif
