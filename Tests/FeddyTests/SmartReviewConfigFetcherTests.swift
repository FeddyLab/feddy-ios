import XCTest
@testable import Feddy

final class SmartReviewConfigFetcherTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "feddy.tests.smartReview.config.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_currentRules_emptyCache_returnsDefault() {
        let rules = SmartReviewConfigFetcher.currentRules(defaults: defaults)
        XCTAssertEqual(rules, .default)
    }

    func test_currentRules_freshCache_returnsCached() throws {
        try writeCache(
            fetchedAt: Date(),
            minDaysSinceInstall: 14,
            minSessions: 10,
            cooldownDays: 30,
            yearlyCap: 2
        )

        let rules = SmartReviewConfigFetcher.currentRules(defaults: defaults)
        XCTAssertEqual(rules.minDaysSinceInstall, 14)
        XCTAssertEqual(rules.minSessions, 10)
        XCTAssertEqual(rules.cooldownDays, 30)
        XCTAssertEqual(rules.yearlyCap, 2)
    }

    func test_currentRules_staleCache_stillReturnsCached() throws {
        // Per Q5 design: stale cache is still better than nothing
        // for *this* call. The presenter is supposed to kick off
        // the background refresh that will replace it for the next
        // call; the engine never blocks on the network.
        try writeCache(
            fetchedAt: Date(timeIntervalSinceNow: -30 * 24 * 60 * 60),
            minDaysSinceInstall: 21,
            minSessions: 8,
            cooldownDays: 60,
            yearlyCap: 1
        )

        let rules = SmartReviewConfigFetcher.currentRules(defaults: defaults)
        XCTAssertEqual(rules.minDaysSinceInstall, 21)
        XCTAssertEqual(rules.minSessions, 8)
    }

    func test_currentRules_corruptCache_returnsDefault() throws {
        defaults.set(Data("not-json-at-all".utf8), forKey: SmartReviewConfigFetcher.cacheKey)

        let rules = SmartReviewConfigFetcher.currentRules(defaults: defaults)
        XCTAssertEqual(rules, .default)
    }

    func test_clearCache_removesEntry() throws {
        try writeCache(
            fetchedAt: Date(),
            minDaysSinceInstall: 7,
            minSessions: 5,
            cooldownDays: 90,
            yearlyCap: 3
        )
        XCTAssertNotNil(defaults.data(forKey: SmartReviewConfigFetcher.cacheKey))

        SmartReviewConfigFetcher.clearCache(defaults: defaults)

        XCTAssertNil(defaults.data(forKey: SmartReviewConfigFetcher.cacheKey))
    }

    // MARK: - helpers

    private struct PersistedCache: Codable {
        let fetchedAt: Date
        let minDaysSinceInstall: Int
        let minSessions: Int
        let cooldownDays: Int
        let yearlyCap: Int
    }

    private func writeCache(
        fetchedAt: Date,
        minDaysSinceInstall: Int,
        minSessions: Int,
        cooldownDays: Int,
        yearlyCap: Int
    ) throws {
        let entry = PersistedCache(
            fetchedAt: fetchedAt,
            minDaysSinceInstall: minDaysSinceInstall,
            minSessions: minSessions,
            cooldownDays: cooldownDays,
            yearlyCap: yearlyCap
        )
        let data = try JSONEncoder().encode(entry)
        defaults.set(data, forKey: SmartReviewConfigFetcher.cacheKey)
    }
}
