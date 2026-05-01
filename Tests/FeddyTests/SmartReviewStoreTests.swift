import XCTest
@testable import Feddy

final class SmartReviewStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: SmartReviewStore!

    override func setUp() {
        super.setUp()
        suiteName = "feddy.tests.smartReview.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = SmartReviewStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - bumpSession

    func test_bumpSession_writesInstallDateOnFirstCall() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.bumpSession(now: now)

        let snap = store.snapshot()
        XCTAssertEqual(snap.installDate, now)
        XCTAssertEqual(snap.sessionCount, 1)
    }

    func test_bumpSession_preservesInstallDateOnSubsequentCalls() {
        let earlier = Date(timeIntervalSince1970: 1_800_000_000)
        let later = Date(timeIntervalSince1970: 1_800_000_100)
        store.bumpSession(now: earlier)
        store.bumpSession(now: later)
        store.bumpSession(now: later)

        let snap = store.snapshot()
        XCTAssertEqual(snap.installDate, earlier)
        XCTAssertEqual(snap.sessionCount, 3)
    }

    // MARK: - markShown

    func test_markShown_setsTimestampAndStartsNewWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.markShown(at: now)

        let snap = store.snapshot()
        XCTAssertEqual(snap.lastShownAt, now)
        XCTAssertEqual(snap.yearlyCount, 1)
        XCTAssertEqual(snap.yearlyWindowStart, now)
    }

    func test_markShown_incrementsYearlyCountInsideWindow() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let t1 = t0.addingTimeInterval(100 * 86_400)
        let t2 = t0.addingTimeInterval(200 * 86_400)
        store.markShown(at: t0)
        store.markShown(at: t1)
        store.markShown(at: t2)

        let snap = store.snapshot()
        XCTAssertEqual(snap.yearlyCount, 3)
        XCTAssertEqual(snap.yearlyWindowStart, t0, "window must not roll while inside 365d")
        XCTAssertEqual(snap.lastShownAt, t2)
    }

    func test_markShown_rollsWindowAfter365Days() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let tAfterYear = t0.addingTimeInterval(366 * 86_400)
        store.markShown(at: t0)
        store.markShown(at: t0.addingTimeInterval(50 * 86_400)) // count -> 2
        store.markShown(at: tAfterYear)

        let snap = store.snapshot()
        XCTAssertEqual(snap.yearlyCount, 1, "rolled window must reset count to 1")
        XCTAssertEqual(snap.yearlyWindowStart, tAfterYear)
        XCTAssertEqual(snap.lastShownAt, tAfterYear)
    }

    // MARK: - clearAll

    func test_clearAll_wipesEveryKey() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.bumpSession(now: now)
        store.bumpSession(now: now)
        store.markShown(at: now)

        store.clearAll()

        let snap = store.snapshot()
        XCTAssertNil(snap.installDate)
        XCTAssertEqual(snap.sessionCount, 0)
        XCTAssertNil(snap.lastShownAt)
        XCTAssertEqual(snap.yearlyCount, 0)
        XCTAssertNil(snap.yearlyWindowStart)
    }
}
