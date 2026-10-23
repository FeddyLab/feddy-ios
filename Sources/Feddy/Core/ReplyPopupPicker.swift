import Foundation

/// What the reply popup shows: the newest unseen reply, plus how many
/// other unread threads it stands in for.
struct ReplyPopupPick: Equatable {
    let conversationId: String
    let authorName: String?
    let message: String?
    let otherCount: Int
    /// Every thread this popup surfaces, with the seq it surfaced at.
    /// Recorded as shown together: a thread folded into "N more" was
    /// put in front of the user too, and popping it on the next launch
    /// would drip a backlog out one card at a time.
    let surfaced: [String: Int]
}

/// Chooses what, if anything, the reply popup shows. Pure so the rules
/// are testable without UIKit: each reply pops at most once, only replies
/// from the last 14 days pop, one card stands for all of them.
enum ReplyPopupPicker {
    /// Older replies keep only the badge: one surfacing months late reads
    /// as noise, and shipping the popup must not dump a backlog on anyone.
    static let maxAge: TimeInterval = 14 * 24 * 60 * 60

    static func pick(
        from conversations: [ConversationSummary],
        shown: [String: Int],
        now: Date = Date()
    ) -> ReplyPopupPick? {
        let cutoff = now.addingTimeInterval(-maxAge)
        // Closed threads count: a reply followed by a close is the common
        // case, and closing says nothing about whether it was read.
        let eligible = conversations.filter {
            $0.hasUnread
                && $0.lastAuthorType != nil
                && $0.lastAuthorType != "contact"
                && $0.lastMessageAt > cutoff
        }
        let fresh = eligible.filter { (shown[$0.id] ?? 0) < $0.lastSeq }
        guard let newest = fresh.max(by: { $0.lastMessageAt < $1.lastMessageAt }) else {
            return nil
        }
        return ReplyPopupPick(
            conversationId: newest.id,
            authorName: newest.lastAuthorName,
            message: newest.lastMessage,
            otherCount: eligible.count - 1,
            surfaced: Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0.lastSeq) })
        )
    }

    /// The shown record after a pick, trimmed to threads still in the
    /// list so it cannot grow without bound. A thread that drops out and
    /// later returns does so with a new reply, which should pop anyway.
    static func record(
        _ pick: ReplyPopupPick?,
        into shown: [String: Int],
        listed conversations: [ConversationSummary]
    ) -> [String: Int] {
        let listed = Set(conversations.map(\.id))
        var next = shown.filter { listed.contains($0.key) }
        for (id, seq) in pick?.surfaced ?? [:] {
            next[id] = max(next[id] ?? 0, seq)
        }
        return next
    }
}
