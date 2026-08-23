import Foundation

/// UI copy, resolved from the package's own bundle so the panel follows
/// the device language instead of whatever the host app happens to ship.
enum Strings {
    static var messages: String { localized("messages") }
    static var newMessage: String { localized("new_message") }
    static var send: String { localized("send") }
    static var composePlaceholder: String { localized("compose_placeholder") }
    static var replyPlaceholder: String { localized("reply_placeholder") }
    static var categoryHint: String { localized("topic") }
    static var categoryChoose: String { localized("topic_choose") }
    static var emptyTitle: String { localized("empty_title") }
    static var emptyBody: String { localized("empty_body") }
    static var submittedFallback: String { localized("submitted_fallback") }
    static var emailPromptTitle: String { localized("email_prompt_title") }
    static var emailPlaceholder: String { localized("email_placeholder") }
    static var emailSave: String { localized("email_save") }
    static var emailSkip: String { localized("email_skip") }
    static var emailInvalid: String { localized("email_invalid") }
    static var closedNotice: String { localized("closed_notice") }
    static var statusClosed: String { localized("status_closed") }
    static var newReply: String { localized("new_reply") }
    static var errorGeneric: String { localized("error_generic") }
    static var rateLimited: String { localized("rate_limited") }
    static var close: String { localized("close") }
    static var cancel: String { localized("cancel") }
    static var done: String { localized("done") }
    static var notificationBody: String { localized("notification_body") }

    /// The four topics every project is seeded with. Their labels live in
    /// the project row as English text, which cannot follow the user's
    /// language, so the SDK supplies its own translation for the seeded
    /// codes. Topics the developer added keep the label they typed.
    static func builtInCategoryLabel(_ code: String) -> String? {
        switch code {
        case "bug", "feature", "question", "other":
            return localized("category.\(code)")
        default:
            return nil
        }
    }

    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}
