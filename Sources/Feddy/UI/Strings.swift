import Foundation

/// UI copy lives in one place; localization can attach here later
/// without touching call sites.
enum Strings {
    static let messages = "Messages"
    static let newMessage = "New message"
    static let send = "Send"
    static let composePlaceholder = "Describe the problem or share an idea…"
    static let replyPlaceholder = "Write a reply…"
    static let categoryHint = "Topic (optional)"
    static let emptyTitle = "No messages yet"
    static let emptyBody = "Questions, bugs, ideas — send us a message and we will get back to you."
    static let submittedFallback = "Got it! We usually reply within 24 hours."
    static let emailPromptTitle = "Want an email when we reply?"
    static let emailPlaceholder = "you@example.com"
    static let emailSave = "Notify me"
    static let emailSkip = "Skip"
    static let emailInvalid = "That email does not look right."
    static let closedNotice =
        "This conversation is closed. Reply within 7 days to continue it; after that a new conversation starts."
    static let statusClosed = "Closed"
    static let newReply = "New reply"
    static let errorGeneric = "Something went wrong. Please try again."
    static let rateLimited = "Too many messages. Please try again later."
    static let close = "Close"
    static let cancel = "Cancel"
    static let done = "Done"
    static let notificationBody = "You have a new reply. Tap to read it."
    static let justNow = "Just now"
}
