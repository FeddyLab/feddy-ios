import Foundation

/// Source of `SmartReviewRules` for the rule engine. Three-layer
/// fallback so the SDK can always produce a usable rule set:
///
/// 1. **Fresh cache** (`fetchedAt` within 24 h) — return immediately,
///    no network.
/// 2. **Server fetch** — kicked off in the background; result writes
///    a new cache entry but doesn't block the current call.
/// 3. **Stale cache** — if the cache is older than 24 h we still
///    use it for the current call; the background fetch above will
///    refresh it for the next one.
/// 4. **Hardcoded default** — when no cache has ever been written
///    (first install) we hand back ``SmartReviewRules/default``.
///
/// This means a freshly installed app with the SDK present but no
/// network gets the conservative 7 / 5 / 90 / 3 defaults, and a
/// network-enabled install converges on whatever the workspace's
/// dashboard rule says within 24 h of the change being saved.
enum SmartReviewConfigFetcher {
    static let cacheKey = "app.feddy.smartReview.config.cache"
    static let cacheTTLSeconds: TimeInterval = 24 * 60 * 60

    /// What the rule engine should evaluate against right now. Reads
    /// the cache; returns the bundled default on cache miss. Callers
    /// must still kick off ``refreshInBackground(client:)`` so the
    /// next invocation sees an up-to-date rule.
    static func currentRules(
        defaults: UserDefaults = .standard
    ) -> SmartReviewRules {
        if let cached = readCache(defaults: defaults) {
            return cached.rules
        }
        return .default
    }

    /// Fire-and-forget refresh. Network failure swallowed and logged;
    /// the next call re-tries on the next presenter invocation.
    @available(iOS 15.0, macOS 12.0, *)
    static func refreshInBackground(
        client: FeddyClient,
        defaults: UserDefaults = .standard
    ) {
        // Skip the network round-trip if the cache is still fresh —
        // the presenter is only called intermittently, but a hot
        // navigation loop could trigger it many times in quick
        // succession (e.g. multiple "save succeeded" hooks).
        if let cached = readCache(defaults: defaults), cached.isFresh {
            return
        }
        Task {
            do {
                let response: ConfigResponse = try await client.get(
                    path: "/v1/config",
                    query: ["kind": "smart_review"]
                )
                let entry = CacheEntry(
                    fetchedAt: Date(),
                    minDaysSinceInstall: response.rule.minDaysSinceInstall,
                    minSessions: response.rule.minSessions,
                    cooldownDays: response.rule.cooldownDays,
                    yearlyCap: response.rule.yearlyCap
                )
                if let data = try? JSONEncoder().encode(entry) {
                    defaults.set(data, forKey: cacheKey)
                }
            } catch {
                print(
                    "[Feddy] Smart Review config refresh failed — \(error.localizedDescription)"
                )
            }
        }
    }

    /// Wipes the cache. Backs ``Feddy/resetSmartReviewState()``'s
    /// "force everything to defaults" intent during debug.
    static func clearCache(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: cacheKey)
    }

    // MARK: - Cache

    private static func readCache(defaults: UserDefaults) -> CacheEntry? {
        guard let data = defaults.data(forKey: cacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }
}

/// Persisted in `UserDefaults` under
/// `app.feddy.smartReview.config.cache`. Snake-case keys would mirror
/// the wire format, but the cache is owned by the SDK and never
/// leaves the device, so we keep camelCase for Swift ergonomics.
private struct CacheEntry: Codable {
    let fetchedAt: Date
    let minDaysSinceInstall: Int
    let minSessions: Int
    let cooldownDays: Int
    let yearlyCap: Int

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt)
            < SmartReviewConfigFetcher.cacheTTLSeconds
    }

    var rules: SmartReviewRules {
        SmartReviewRules(
            minDaysSinceInstall: minDaysSinceInstall,
            minSessions: minSessions,
            cooldownDays: cooldownDays,
            yearlyCap: yearlyCap
        )
    }
}

/// Server response shape — `GET /v1/config?kind=smart_review`.
private struct ConfigResponse: Decodable {
    let kind: String
    let rule: ConfigRule
}

private struct ConfigRule: Decodable {
    let minDaysSinceInstall: Int
    let minSessions: Int
    let cooldownDays: Int
    let yearlyCap: Int

    enum CodingKeys: String, CodingKey {
        case minDaysSinceInstall = "min_days_since_install"
        case minSessions = "min_sessions"
        case cooldownDays = "cooldown_days"
        case yearlyCap = "yearly_cap"
    }
}
