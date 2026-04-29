import Foundation

/// A tiny FIFO queue persisted in `UserDefaults`, used to retry
/// `submitRequest` payloads that hit a network failure or a server-side
/// 5xx. 4xx responses are not retried — they would just fail forever.
///
/// Storage shape: a JSON array of `QueuedItem` under a single key, with a
/// hard cap that drops the oldest entry when full. Each item is at most a
/// few KB (title + description + small metadata), so the cap of 100
/// keeps the encoded blob comfortably under typical `UserDefaults` size
/// limits while covering days of offline use.
struct RequestQueue: @unchecked Sendable {
    static let storageKey = "app.feddy.requestQueue.v1"
    static let defaultCapacity = 100

    let defaults: UserDefaults
    let capacity: Int
    let nowProvider: @Sendable () -> Date
    let idGenerator: @Sendable () -> String

    init(
        defaults: UserDefaults = .standard,
        capacity: Int = RequestQueue.defaultCapacity,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.defaults = defaults
        self.capacity = capacity
        self.nowProvider = nowProvider
        self.idGenerator = idGenerator
    }

    /// One enqueued submitRequest payload. `body` is the already-encoded
    /// JSON object (kept as `Data` so the encoder runs once at enqueue
    /// time, not on every replay).
    struct QueuedItem: Codable, Equatable, Sendable {
        let id: String
        let path: String
        let body: Data
        let createdAt: Date
        var attempts: Int
    }

    var snapshot: [QueuedItem] {
        load()
    }

    var isEmpty: Bool { snapshot.isEmpty }
    var count: Int { snapshot.count }

    /// Append `item` to the tail; if doing so would exceed `capacity`,
    /// drop the oldest entry first (FIFO drop-head). Concurrent enqueues
    /// from different threads are not protected — host apps call
    /// `submitRequest` from a single Task at the actor boundary, and the
    /// race window is tiny in practice. If we ever see lossage in the
    /// wild we'll add a Locked<…> wrapper.
    func enqueue(path: String, body: Data) {
        var items = load()
        let item = QueuedItem(
            id: idGenerator(),
            path: path,
            body: body,
            createdAt: nowProvider(),
            attempts: 0
        )
        items.append(item)
        while items.count > capacity {
            items.removeFirst()
        }
        save(items)
    }

    /// Remove a specific item by id. Used after a successful replay POST.
    func remove(id: String) {
        var items = load()
        items.removeAll { $0.id == id }
        save(items)
    }

    /// Atomically replace the queue contents — used by tests and by the
    /// replay path when bumping `attempts` on an item that should stay
    /// enqueued for another retry.
    func replace(_ items: [QueuedItem]) {
        save(items)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Private

    private func load() -> [QueuedItem] {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return []
        }
        return (try? JSONDecoder.feddy.decode([QueuedItem].self, from: data)) ?? []
    }

    private func save(_ items: [QueuedItem]) {
        if items.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        guard let data = try? JSONEncoder.feddy.encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
