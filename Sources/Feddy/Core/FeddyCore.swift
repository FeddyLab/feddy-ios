import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Internal singleton behind the static `Feddy` facade: holds the
/// configuration, API client, cached config, and unread state.
final class FeddyCore: @unchecked Sendable {
    static let shared = FeddyCore()

    private(set) var client: APIClient?
    private var mayRequestNotificationPermission = false
    private(set) var config: FeddyConfig?
    private(set) var unreadCount = 0

    private let stateQueue = DispatchQueue(label: "app.feddy.sdk.state")
    private var notifiedSeqs: [String: Int]
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    /// Spec 5.1: the entry-point badge is fed by a foreground poll as well
    /// as by explicit refreshes. iOS suspends the task in the background,
    /// so this costs nothing while the app is away.
    private static let pollInterval: UInt64 = 30_000_000_000

    private static let notifiedSeqsKey = "feddy.notified_seqs"
    private static let emailKnownKey = "feddy.email_known"
    private static let notificationsRequestedKey = "feddy.notifications_requested"

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.notifiedSeqsKey) as? [String: Int]
        notifiedSeqs = stored ?? [:]
    }

    var isConfigured: Bool { client != nil }

    // MARK: - Lifecycle

    func configure(projectId: String, apiURL: URL, requestsNotificationPermission: Bool) {
        guard client == nil else { return }
        mayRequestNotificationPermission = requestsNotificationPermission
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

    // MARK: - Unread + local notifications

    /// Pulls the unread count (entry-point badge) and posts local
    /// notifications for replies that arrived since the last check.
    func refresh() {
        guard let client else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            if let unread = try? await client.unreadCount() {
                self.setUnread(unread.unreadCount)
            }
            await self.notifyNewReplies(client: client)
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
        Task { @MainActor in Feddy.onUnreadCountChanged?(count) }
    }

    private func notifyNewReplies(client: APIClient) async {
        guard let list = try? await client.conversations() else { return }
        var pending: [(conversation: ConversationSummary, seq: Int)] = []
        stateQueue.sync {
            for conversation in list.conversations where conversation.hasUnread {
                let notified = notifiedSeqs[conversation.id] ?? conversation.seenSeq
                if conversation.lastSeq > notified {
                    pending.append((conversation, conversation.lastSeq))
                    notifiedSeqs[conversation.id] = conversation.lastSeq
                }
            }
            UserDefaults.standard.set(notifiedSeqs, forKey: Self.notifiedSeqsKey)
        }
        guard !pending.isEmpty else { return }
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        for item in pending {
            let content = UNMutableNotificationContent()
            content.title = config?.brand.name ?? "Support"
            content.body = Strings.notificationBody
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "feddy-\(item.conversation.id)-\(item.seq)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
        #endif
    }

    /// Asked once, after the first successful submission — never at
    /// configure time, so the permission prompt has context.
    ///
    /// Only when the host app opted in: the system prompt can be answered
    /// once per install, and a refusal costs the host every notification it
    /// might want later. Replies still surface as local notifications when
    /// permission is already granted, and by email regardless.
    func requestNotificationPermissionIfNeeded() {
        guard mayRequestNotificationPermission else { return }
        #if canImport(UserNotifications)
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.notificationsRequestedKey) else { return }
        defaults.set(true, forKey: Self.notificationsRequestedKey)
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
        #endif
    }

    // MARK: - Email capture state

    var emailKnown: Bool {
        UserDefaults.standard.bool(forKey: Self.emailKnownKey)
    }

    func markEmailKnown() {
        UserDefaults.standard.set(true, forKey: Self.emailKnownKey)
    }
}
