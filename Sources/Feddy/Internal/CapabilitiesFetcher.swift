import Foundation

/// Source of the workspace's capabilities payload (currently only the
/// `branding` block — what to render in `PoweredByBadge` footers).
/// Three-layer fallback so the SDK can always make a render decision:
///
/// 1. **Fresh cache** (`fetchedAt` within 24 h) — return immediately.
/// 2. **Stale cache** — still used for the current call; the
///    background refresh will replace it for the next one.
/// 3. **Hardcoded fallback** — when no cache has ever been written
///    (first install, network failure) we hand back ``Branding/fallback``
///    so a Free workspace's badge always shows. Pro workspaces with a
///    cached `branding: nil` resolve to `nil` → `EmptyView()`.
enum CapabilitiesFetcher {
    static let cacheKey = "app.feddy.capabilities.cache"
    static let cacheTTLSeconds: TimeInterval = 24 * 60 * 60

    /// What `PoweredByBadge` should render right now. Reads the
    /// cache; returns the bundled fallback on cache miss. Callers
    /// must still kick off ``refreshInBackground(client:)`` so the
    /// next call converges on the workspace's actual plan.
    static func currentBranding(
        defaults: UserDefaults = .standard
    ) -> Branding? {
        if let cached = readCache(defaults: defaults) {
            return cached.branding
        }
        return .fallback
    }

    /// Fire-and-forget refresh. Skips the round-trip when the cache
    /// is still fresh — the badge can be re-rendered many times in a
    /// session (each view's `.task` triggers a refresh attempt).
    @available(iOS 15.0, macOS 12.0, *)
    static func refreshInBackground(
        client: FeddyClient,
        defaults: UserDefaults = .standard
    ) {
        if let cached = readCache(defaults: defaults), cached.isFresh {
            return
        }
        Task {
            do {
                let response: CapabilitiesResponse = try await client.get(
                    path: "/v1/capabilities"
                )
                let entry = CacheEntry(
                    fetchedAt: Date(),
                    branding: response.branding
                )
                if let data = try? JSONEncoder().encode(entry) {
                    defaults.set(data, forKey: cacheKey)
                }
            } catch {
                print(
                    "[Feddy] capabilities refresh failed — \(error.localizedDescription)"
                )
            }
        }
    }

    /// Wipes the cache. Backs ``Feddy/reset()``'s "force everything
    /// to defaults" intent so a logged-out integrator picking up a
    /// different workspace doesn't see the previous workspace's
    /// branding decision.
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

/// Branding payload returned by `GET /v1/capabilities`. `nil` at the
/// API boundary means a Pro/Team workspace — the SDK renders nothing.
struct Branding: Codable, Equatable {
    let show: Bool
    let text: String
    let url: String
    let logoUrl: String?

    enum CodingKeys: String, CodingKey {
        case show
        case text
        case url
        case logoUrl = "logo_url"
    }

    /// Hardcoded fallback for the very first launch when no cache
    /// has been written yet. Favors showing the badge so a Free
    /// workspace doesn't get a silent free pass while offline.
    static let fallback = Branding(
        show: true,
        text: "Powered by Feddy",
        url: "https://feddy.app",
        logoUrl: nil
    )
}

/// Persisted in `UserDefaults` under
/// `app.feddy.capabilities.cache`. `branding == nil` is a meaningful
/// value (Pro/Team workspace), distinct from "no cache entry" — that
/// distinction is what lets the in-app render flip off without a
/// network call once a Pro plan is observed.
private struct CacheEntry: Codable {
    let fetchedAt: Date
    let branding: Branding?

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt)
            < CapabilitiesFetcher.cacheTTLSeconds
    }
}

private struct CapabilitiesResponse: Decodable {
    let branding: Branding?
}
