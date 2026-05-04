import XCTest
@testable import Feddy

final class CapabilitiesFetcherTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "feddy.tests.capabilities.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // First-launch path: nothing cached → render the hardcoded
    // fallback so the badge never silently disappears for a Free
    // workspace that just happens to be offline.
    func test_currentBranding_emptyCache_returnsFallback() {
        let branding = CapabilitiesFetcher.currentBranding(defaults: defaults)
        XCTAssertEqual(branding, .fallback)
        XCTAssertEqual(branding?.text, "Powered by Feddy")
        XCTAssertEqual(branding?.url, "https://feddy.app")
    }

    // Paid workspace path: server returned `branding: null` and we
    // cached that fact. Subsequent reads must resolve to nil so the
    // badge renders nothing — distinct from the empty-cache case
    // above which returns the fallback.
    func test_currentBranding_cachedNil_returnsNil() throws {
        try writeCache(fetchedAt: Date(), branding: nil)

        let branding = CapabilitiesFetcher.currentBranding(defaults: defaults)
        XCTAssertNil(branding)
    }

    func test_currentBranding_cachedFreeBranding_returnsCached() throws {
        let payload = Branding(
            show: true,
            text: "Custom Free Text",
            url: "https://example.com",
            logoUrl: "https://example.com/logo.svg"
        )
        try writeCache(fetchedAt: Date(), branding: payload)

        let branding = CapabilitiesFetcher.currentBranding(defaults: defaults)
        XCTAssertEqual(branding, payload)
    }

    // Stale cache (>24h) is still authoritative for the current call;
    // refreshInBackground will replace it for the next one. This
    // matches the SmartReviewConfigFetcher pattern — the engine never
    // blocks on the network.
    func test_currentBranding_staleCache_stillReturnsCached() throws {
        let payload = Branding(
            show: true,
            text: "Stale But Valid",
            url: "https://feddy.app",
            logoUrl: nil
        )
        try writeCache(
            fetchedAt: Date(timeIntervalSinceNow: -30 * 24 * 60 * 60),
            branding: payload
        )

        let branding = CapabilitiesFetcher.currentBranding(defaults: defaults)
        XCTAssertEqual(branding, payload)
    }

    func test_currentBranding_corruptCache_returnsFallback() {
        defaults.set(
            Data("not-json-at-all".utf8),
            forKey: CapabilitiesFetcher.cacheKey
        )

        let branding = CapabilitiesFetcher.currentBranding(defaults: defaults)
        XCTAssertEqual(branding, .fallback)
    }

    func test_clearCache_removesEntry() throws {
        try writeCache(fetchedAt: Date(), branding: .fallback)
        XCTAssertNotNil(defaults.data(forKey: CapabilitiesFetcher.cacheKey))

        CapabilitiesFetcher.clearCache(defaults: defaults)

        XCTAssertNil(defaults.data(forKey: CapabilitiesFetcher.cacheKey))
    }

    func test_branding_decodesSnakeCaseLogoUrl() throws {
        let json = """
        {
            "show": true,
            "text": "Powered by Feddy",
            "url": "https://feddy.app",
            "logo_url": "https://assets.feddy.app/badge-mini.svg"
        }
        """.data(using: .utf8)!

        let branding = try JSONDecoder().decode(Branding.self, from: json)
        XCTAssertEqual(branding.logoUrl, "https://assets.feddy.app/badge-mini.svg")
    }

    // MARK: - helpers

    private struct PersistedCache: Codable {
        let fetchedAt: Date
        let branding: Branding?
    }

    private func writeCache(fetchedAt: Date, branding: Branding?) throws {
        let entry = PersistedCache(fetchedAt: fetchedAt, branding: branding)
        let data = try JSONEncoder().encode(entry)
        defaults.set(data, forKey: CapabilitiesFetcher.cacheKey)
    }
}
