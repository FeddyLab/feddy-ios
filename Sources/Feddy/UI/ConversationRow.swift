#if canImport(UIKit)
import SwiftUI

/// One conversation as the home screen and the full list show it: the
/// project's face, the latest thing said, who said it and when.
struct ConversationRow: View {
    let conversation: ConversationSummary
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            BrandMark(size: 36)
            VStack(alignment: .leading, spacing: 3) {
                // An inbox row is the latest thing said, not the opener; the
                // opener is what an older server gives us.
                Text(conversation.lastMessage ?? conversation.subject ?? "…")
                    .font(.subheadline.weight(conversation.hasUnread ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let who = author {
                        Text(who)
                        Text("·")
                    }
                    Text(Self.relativeFormatter.localizedString(for: conversation.lastMessageAt, relativeTo: Date()))
                    if conversation.status == "closed" {
                        Text(Strings.statusClosed)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.surface)
                            .clipShape(Capsule())
                            .padding(.leading, 2)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Circle()
                .fill(conversation.hasUnread ? accent : Color.clear)
                .frame(width: 8, height: 8)
                .accessibilityLabel(conversation.hasUnread ? Strings.newReply : "")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var author: String? {
        switch conversation.lastAuthorType {
        case nil:
            return nil
        case "contact":
            return Strings.you
        default:
            return conversation.lastAuthorName ?? FeddyCore.shared.config?.brand.name
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

/// The project's logo, or its initial on the brand colour when there is
/// none — the same mark the web widget draws.
struct BrandMark: View {
    let size: CGFloat

    private var config: FeddyConfig? { FeddyCore.shared.config }

    var body: some View {
        Group {
            if let logo = config?.brand.logoUrl, let url = URL(string: logo) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Theme.surface
                }
            } else {
                ZStack {
                    Theme.accent(config)
                    Text(initial)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(Theme.onAccent(config))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .accessibilityHidden(true)
    }

    private var initial: String {
        (config?.brand.name.first).map { String($0).uppercased() } ?? "F"
    }
}
#endif
