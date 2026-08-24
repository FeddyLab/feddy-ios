import Foundation

/// Internal singleton behind the static `Feddy` facade: holds the
/// configuration, API client, cached config, and unread state.
final class FeddyCore: @unchecked Sendable {
    static let shared = FeddyCore()

    private(set) var client: APIClient?
    private(set) var config: FeddyConfig?
    private(set) var unreadCount = 0

    private let stateQueue = DispatchQueue(label: "app.feddy.sdk.state")
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    /// Spec 5.1: the entry-point badge is fed by a foreground poll as well
    /// as by explicit refreshes. iOS suspends the task in the background,
    /// so this costs nothing while the app is away.
    private static let pollInterval: UInt64 = 30_000_000_000

    private static let emailKnownKey = "feddy.email_known"
    private static let emailAskDismissedKey = "feddy.email_ask_dismissed"

    private init() {}

    var isConfigured: Bool { client != nil }

    // MARK: - Lifecycle

    func configure(projectId: String, apiURL: URL) {
        guard client == nil else { return }
        client = APIClient(projectId: projectId, baseURL: apiURL, anonId: AnonIdStore.anonId())
        Task { await self.loadConfig() }
        refresh()
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    func loadConfig() async {
        guard let client, config == nil else { return }
        config = try? await client.config()
    }

    // MARK: - Unread

    /// Pulls the unread count that feeds the entry-point badge.
    func refresh() {
        guard let client else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            if let unread = try? await client.unreadCount() {
                self.setUnread(unread.unreadCount)
            }
        }
    }

    func unreadCount(_ completion: @escaping (Int) -> Void) {
        guard let client else {
            completion(0)
            return
        }
        Task {
            let count = (try? await client.unreadCount())?.unreadCount ?? 0
            self.setUnread(count)
            DispatchQueue.main.async { completion(count) }
        }
    }

    func setUnread(_ count: Int) {
        let changed = stateQueue.sync { () -> Bool in
            guard unreadCount != count else { return false }
            unreadCount = count
            return true
        }
        guard changed else { return }
        Task { @MainActor in
            FeddyUnread.shared.update(count)
            Feddy.onUnreadCountChanged?(count)
        }
    }

    // MARK: - Email capture state

    var emailKnown: Bool {
        UserDefaults.standard.bool(forKey: Self.emailKnownKey)
    }

    func markEmailKnown() {
        UserDefaults.standard.set(true, forKey: Self.emailKnownKey)
    }

    /// Skipping is a decision, not per-screen state. Held only in a view's
    /// `@State`, it reset on every visit to a thread and on every submit,
    /// so someone who had already declined kept being asked. Once this is
    /// set the SDK never asks unprompted again; the thread's toolbar button
    /// stays as the way back in.
    var emailAskDismissed: Bool {
        UserDefaults.standard.bool(forKey: Self.emailAskDismissedKey)
    }

    func markEmailAskDismissed() {
        UserDefaults.standard.set(true, forKey: Self.emailAskDismissedKey)
    }
}
