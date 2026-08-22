import Foundation

/// In-app support for your users: submit feedback, get replies, done.
///
/// ```swift
/// Feddy.configure(projectId: "fd_...")
/// Feddy.present()
/// ```
public enum Feddy {
    /// Fired on the main thread whenever the unread count changes.
    /// Drive your own badge with it.
    ///
    /// Main-actor isolated: a bare mutable static is not concurrency-safe,
    /// and referencing one is a hard error under the Swift 6 language mode.
    @MainActor
    public static var onUnreadCountChanged: ((Int) -> Void)?

    /// Call once at launch (AppDelegate or `App.init`). Subsequent calls
    /// are ignored.
    /// - Parameter projectId: the project's ID, copied from the dashboard.
    ///   It ships inside your binary, so it is public by design — checking it
    ///   into source control is fine.
    public static func configure(
        projectId: String,
        apiURL: URL = URL(string: "https://core.feddy.app")!
    ) {
        FeddyCore.shared.configure(projectId: projectId, apiURL: apiURL)
    }

    /// Optionally bind the logged-in user. Attribute values may be
    /// `String`, `Bool`, numbers, or `Date`; other types are dropped.
    public static func identify(
        userId: String,
        email: String? = nil,
        name: String? = nil,
        attributes: [String: Any] = [:]
    ) {
        guard let client = FeddyCore.shared.client else { return }
        if email != nil { FeddyCore.shared.markEmailKnown() }
        Task {
            _ = try? await client.identify(
                externalId: userId, email: email, name: name, attributes: attributes
            )
        }
    }

    /// Fetches the current unread count (completion on the main thread).
    public static func unreadCount(_ completion: @escaping (Int) -> Void) {
        FeddyCore.shared.unreadCount(completion)
    }

    /// Re-pulls unread state and posts local notifications for new
    /// replies. Call when your app enters the foreground.
    public static func refresh() {
        FeddyCore.shared.refresh()
    }

    #if canImport(UIKit)
    /// Presents the conversation list over the current screen. Works
    /// from UIKit and SwiftUI hosts alike.
    @MainActor
    public static func present() {
        Presenter.present(startInCompose: false)
    }

    /// Presents the UI straight into the new-message form.
    @MainActor
    public static func presentNewConversation() {
        Presenter.present(startInCompose: true)
    }
    #endif
}
