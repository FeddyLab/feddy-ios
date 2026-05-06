import XCTest
@testable import Feddy

final class BoardsCacheTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "feddy.tests.boards.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_currentBoards_emptyCache_returnsNil() {
        XCTAssertNil(BoardsCache.currentBoards(defaults: defaults))
    }

    func test_currentBoards_cachedFresh_returnsCached() throws {
        try writeCache(
            fetchedAt: Date(),
            boards: [
                FeedbackBoard(key: "features", name: "Features"),
                FeedbackBoard(key: "roadmap-2026", name: "Roadmap 2026"),
            ]
        )
        let boards = BoardsCache.currentBoards(defaults: defaults)
        XCTAssertEqual(boards?.count, 2)
        XCTAssertEqual(boards?.first?.key, "features")
        XCTAssertEqual(boards?.last?.key, "roadmap-2026")
    }

    func test_isFresh_freshEntry_returnsTrue() throws {
        try writeCache(fetchedAt: Date(), boards: [])
        XCTAssertTrue(BoardsCache.isFresh(defaults: defaults))
    }

    func test_isFresh_staleEntry_returnsFalse() throws {
        let stale = Date(timeIntervalSinceNow: -7200) // 2h ago, TTL is 1h
        try writeCache(fetchedAt: stale, boards: [])
        XCTAssertFalse(BoardsCache.isFresh(defaults: defaults))
    }

    // Stale cache is still served on the current call so the picker is
    // never empty mid-session. Only the next call sees the refreshed
    // payload.
    func test_currentBoards_staleCache_stillReturnsCached() throws {
        let stale = Date(timeIntervalSinceNow: -7200)
        try writeCache(
            fetchedAt: stale,
            boards: [FeedbackBoard(key: "bugs", name: "Bug Reports")]
        )
        XCTAssertEqual(
            BoardsCache.currentBoards(defaults: defaults)?.first?.key,
            "bugs"
        )
    }

    func test_clearCache_wipesEntry() throws {
        try writeCache(
            fetchedAt: Date(),
            boards: [FeedbackBoard(key: "features", name: "Features")]
        )
        BoardsCache.clearCache(defaults: defaults)
        XCTAssertNil(BoardsCache.currentBoards(defaults: defaults))
    }

    func test_currentBoards_corruptedJSON_returnsNil() {
        defaults.set(Data("not json".utf8), forKey: BoardsCache.cacheKey)
        XCTAssertNil(BoardsCache.currentBoards(defaults: defaults))
    }

    private func writeCache(
        fetchedAt: Date,
        boards: [FeedbackBoard]
    ) throws {
        struct Entry: Encodable {
            let fetchedAt: Date
            let boards: [FeedbackBoard]
        }
        let data = try JSONEncoder.feddy.encode(
            Entry(fetchedAt: fetchedAt, boards: boards)
        )
        defaults.set(data, forKey: BoardsCache.cacheKey)
    }
}

final class BoardLocalizationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BoardLocalization.clearHostTranslations()
    }

    override func tearDown() {
        BoardLocalization.clearHostTranslations()
        super.tearDown()
    }

    // System keys always resolve through the bundled xcstrings catalog.
    // Whatever the host or server provides as `fallbackName` is
    // ignored — keeps first-party UI consistent with iOS / Android /
    // RN siblings.
    func test_systemKey_resolvesViaCatalog_ignoringFallback() {
        let result = BoardLocalization.localizedName(
            "features",
            fallbackName: "Server English Override"
        )
        // Catalog returns either the localized string for the device
        // locale or the key itself as a last-ditch fallback when
        // nothing matched. Either way, the host's "Server English
        // Override" string must NOT appear.
        XCTAssertNotEqual(result, "Server English Override")
        XCTAssertFalse(result.isEmpty)
    }

    // System keys ignore host-provided translations even when the
    // host explicitly wires up a `features` entry.
    func test_systemKey_ignoresHostOverride() {
        BoardLocalization.setHostTranslations([
            "features": ["en": "My Custom Features Label"],
        ])
        let result = BoardLocalization.localizedName(
            "features",
            fallbackName: "Features"
        )
        XCTAssertNotEqual(result, "My Custom Features Label")
    }

    // Custom key, no host translation, no fallback → capitalized key
    // so the picker is never empty.
    func test_customKey_noFallback_returnsCapitalized() {
        XCTAssertEqual(
            BoardLocalization.localizedName("experiments"),
            "Experiments"
        )
    }

    // Custom key with server-supplied name passes through untouched.
    func test_customKey_returnsFallback() {
        XCTAssertEqual(
            BoardLocalization.localizedName(
                "roadmap-2026",
                fallbackName: "Roadmap 2026"
            ),
            "Roadmap 2026"
        )
    }

    // Empty fallback is treated as missing, falling through to
    // capitalize.
    func test_customKey_emptyFallback_returnsCapitalized() {
        XCTAssertEqual(
            BoardLocalization.localizedName("beta", fallbackName: ""),
            "Beta"
        )
    }

    // Empty key returns empty string — a missing board reference
    // should never render UI text.
    func test_emptyKey_returnsEmpty() {
        XCTAssertEqual(BoardLocalization.localizedName(""), "")
    }

    // Host translation table is consulted for custom keys.
    func test_hostTranslation_currentLocale_isReturned() {
        // Pull the current locale code so this test is portable across
        // device locales — the precedence rule is what we care about,
        // not which specific locale the runner is on.
        let code = currentTestLocaleCode()
        BoardLocalization.setHostTranslations([
            "design": [code: "Resolved-By-Host"],
        ])
        XCTAssertEqual(
            BoardLocalization.localizedName(
                "design",
                fallbackName: "Server Design"
            ),
            "Resolved-By-Host"
        )
    }

    // Host has translations for some custom key but not the current
    // locale → fallback to server name (admin's dashboard input).
    func test_hostTranslation_otherLocale_fallsBackToServer() {
        // Provide a translation for a clearly-not-current locale so
        // the lookup misses regardless of where this test runs.
        let foreignCode = currentTestLocaleCode() == "en" ? "ja" : "en"
        BoardLocalization.setHostTranslations([
            "design": [foreignCode: "Will Not Be Used"],
        ])
        XCTAssertEqual(
            BoardLocalization.localizedName(
                "design",
                fallbackName: "Server Design"
            ),
            "Server Design"
        )
    }

    func test_clearHostTranslations_wipesTable() {
        let code = currentTestLocaleCode()
        BoardLocalization.setHostTranslations([
            "design": [code: "Resolved-By-Host"],
        ])
        BoardLocalization.clearHostTranslations()
        XCTAssertEqual(
            BoardLocalization.localizedName(
                "design",
                fallbackName: "Server Design"
            ),
            "Server Design"
        )
    }

    // localize(_:) returns the original board untouched when no
    // translation rule applies, so the array round-trips cleanly
    // through fetchBoards mapping.
    func test_localizeBoard_customKeyNoTranslation_returnsOriginal() {
        let board = FeedbackBoard(key: "design", name: "Server Design")
        XCTAssertEqual(BoardLocalization.localize(board), board)
    }

    func test_localizeBoard_hostOverride_returnsLocalizedName() {
        let code = currentTestLocaleCode()
        BoardLocalization.setHostTranslations([
            "roadmap-2026": [code: "Roadmap 2026 Localized"],
        ])
        let original = FeedbackBoard(
            key: "roadmap-2026",
            name: "Roadmap 2026 Server"
        )
        XCTAssertEqual(
            BoardLocalization.localize(original).name,
            "Roadmap 2026 Localized"
        )
    }

    private func currentTestLocaleCode() -> String {
        if #available(iOS 16.0, macOS 13.0, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        return Locale.current.languageCode ?? "en"
    }
}
