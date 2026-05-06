import Foundation

/// 1 h cache of the workspace's public, non-archived boards
/// (`GET /v1/boards`). Mirrors ``CapabilitiesFetcher`` in shape — the
/// two caches share a layout deliberately so future cleanup can lift
/// them into a generic helper.
///
/// Stale-while-revalidate semantics: a cache hit (even if stale) is
/// returned immediately; if the entry is past its TTL a background
/// refresh is kicked off so the next call sees fresh data. First-launch
/// network failure resolves to the SDK's bundled
/// ``FeedbackBoard/systemDefaults`` so picker UIs are never empty.
enum BoardsCache {
    static let cacheKey = "app.feddy.boards.cache"
    static let cacheTTLSeconds: TimeInterval = 60 * 60

    /// Read whatever the cache currently holds, regardless of freshness.
    /// Returns `nil` only when no entry has ever been written (first
    /// launch + offline). Callers should pair this with
    /// ``refreshInBackground(client:)`` so the next call converges.
    static func currentBoards(
        defaults: UserDefaults = .standard
    ) -> [FeedbackBoard]? {
        readCache(defaults: defaults)?.boards
    }

    /// Whether the on-disk entry is fresh enough to skip a refresh.
    static func isFresh(defaults: UserDefaults = .standard) -> Bool {
        guard let entry = readCache(defaults: defaults) else { return false }
        return entry.isFresh
    }

    /// Fire-and-forget background refresh. Skips the round-trip when
    /// the cache is still fresh.
    @available(iOS 15.0, macOS 12.0, *)
    static func refreshInBackground(
        client: FeddyClient,
        defaults: UserDefaults = .standard
    ) {
        if isFresh(defaults: defaults) { return }
        Task {
            do {
                let response: BoardsResponse = try await client.get(
                    path: "/v1/boards"
                )
                let entry = CacheEntry(
                    fetchedAt: Date(),
                    boards: response.items
                )
                if let data = try? JSONEncoder.feddy.encode(entry) {
                    defaults.set(data, forKey: cacheKey)
                }
            } catch {
                print(
                    "[Feddy] boards refresh failed — \(error.localizedDescription)"
                )
            }
        }
    }

    /// Synchronous fetch path used by the public ``Feddy/fetchBoards()``
    /// when no cache exists yet. Hits the network once and writes the
    /// result on success. Throws on network failure so the caller can
    /// fall back to ``FeedbackBoard/systemDefaults``.
    @available(iOS 15.0, macOS 12.0, *)
    static func fetchOnce(
        client: FeddyClient,
        defaults: UserDefaults = .standard
    ) async throws -> [FeedbackBoard] {
        let response: BoardsResponse = try await client.get(path: "/v1/boards")
        let entry = CacheEntry(fetchedAt: Date(), boards: response.items)
        if let data = try? JSONEncoder.feddy.encode(entry) {
            defaults.set(data, forKey: cacheKey)
        }
        return response.items
    }

    /// Wipe the cache. Hooked into ``Feddy/reset()`` so a logged-out
    /// integrator picking up a different workspace doesn't see the
    /// previous workspace's board list.
    static func clearCache(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: cacheKey)
    }

    // MARK: - Cache

    private static func readCache(defaults: UserDefaults) -> CacheEntry? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder.feddy.decode(CacheEntry.self, from: data)
    }
}

/// Server response shape for `GET /v1/boards`.
private struct BoardsResponse: Decodable {
    let items: [FeedbackBoard]
}

/// On-disk entry under `app.feddy.boards.cache`.
private struct CacheEntry: Codable {
    let fetchedAt: Date
    let boards: [FeedbackBoard]

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < BoardsCache.cacheTTLSeconds
    }
}
