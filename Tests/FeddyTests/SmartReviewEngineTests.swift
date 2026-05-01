import XCTest
@testable import Feddy

final class SmartReviewEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let defaultRules = SmartReviewRules.default // 7 / 5 / 90 / 3

    // MARK: - Gate 1: minDaysSinceInstall

    func test_skipsWhenInstallDateMissing() {
        let state = SmartReviewState(
            installDate: nil,
            sessionCount: 100,
            lastShownAt: nil,
            yearlyCount: 0,
            yearlyWindowStart: nil
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .skipBelowDaysSinceInstall(observed: 0, required: 7))
    }

    func test_skipsWhenInstallTooRecent() {
        let installDate = now.addingTimeInterval(-3 * 86_400) // 3 days ago
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 100,
            lastShownAt: nil,
            yearlyCount: 0,
            yearlyWindowStart: nil
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .skipBelowDaysSinceInstall(observed: 3, required: 7))
    }

    func test_passesGate1AtExactly7Days() {
        let installDate = now.addingTimeInterval(-7 * 86_400 - 1) // 7 days + 1 second ago
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 100,
            lastShownAt: nil,
            yearlyCount: 0,
            yearlyWindowStart: nil
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .show)
    }

    func test_skipsAt6DaysAnd23Hours() {
        // Off-by-one guard: less-than rule, not less-or-equal.
        let installDate = now.addingTimeInterval(-(7 * 86_400 - 1)) // 6d 23h 59m 59s ago
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 100,
            lastShownAt: nil,
            yearlyCount: 0,
            yearlyWindowStart: nil
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .skipBelowDaysSinceInstall(observed: 6, required: 7))
    }

    // MARK: - Gate 2: minSessions

    func test_skipsWhenSessionsBelowMin() {
        let installDate = now.addingTimeInterval(-30 * 86_400)
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 4,
            lastShownAt: nil,
            yearlyCount: 0,
            yearlyWindowStart: nil
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .skipBelowSessions(observed: 4, required: 5))
    }

    // MARK: - Gate 3: cooldown

    func test_skipsWhenCooldownStillActive() {
        let installDate = now.addingTimeInterval(-100 * 86_400)
        let lastShownAt = now.addingTimeInterval(-30 * 86_400)
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 50,
            lastShownAt: lastShownAt,
            yearlyCount: 1,
            yearlyWindowStart: lastShownAt
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .skipInCooldown(observedDays: 30, requiredDays: 90))
    }

    func test_passesAfterCooldown() {
        let installDate = now.addingTimeInterval(-200 * 86_400)
        let lastShownAt = now.addingTimeInterval(-95 * 86_400)
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 50,
            lastShownAt: lastShownAt,
            yearlyCount: 1,
            yearlyWindowStart: lastShownAt
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .show)
    }

    // MARK: - Gate 4: yearly cap

    func test_skipsWhenYearlyCapReachedInsideWindow() {
        let installDate = now.addingTimeInterval(-300 * 86_400)
        let windowStart = now.addingTimeInterval(-200 * 86_400)
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 50,
            lastShownAt: now.addingTimeInterval(-100 * 86_400),
            yearlyCount: 3,
            yearlyWindowStart: windowStart
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .skipYearlyCapReached(observed: 3, cap: 3))
    }

    func test_yearlyCapIgnoredWhenWindowExpired() {
        // Window started > 365 days ago → cap doesn't apply, store
        // will reset on next markShown.
        let installDate = now.addingTimeInterval(-500 * 86_400)
        let windowStart = now.addingTimeInterval(-400 * 86_400)
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 50,
            lastShownAt: now.addingTimeInterval(-100 * 86_400),
            yearlyCount: 5,
            yearlyWindowStart: windowStart
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .show)
    }

    // MARK: - All gates pass

    func test_allGatesPassReturnsShow() {
        let installDate = now.addingTimeInterval(-30 * 86_400)
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 10,
            lastShownAt: nil,
            yearlyCount: 0,
            yearlyWindowStart: nil
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: defaultRules)
        XCTAssertEqual(decision, .show)
    }

    func test_customRulesRespected() {
        // Stricter rule set: 30 days install, 50 sessions.
        let strict = SmartReviewRules(
            minDaysSinceInstall: 30,
            minSessions: 50,
            cooldownDays: 180,
            yearlyCap: 1
        )
        let installDate = now.addingTimeInterval(-15 * 86_400) // half of strict
        let state = SmartReviewState(
            installDate: installDate,
            sessionCount: 100,
            lastShownAt: nil,
            yearlyCount: 0,
            yearlyWindowStart: nil
        )
        let decision = SmartReviewEngine.eval(now: now, state: state, rules: strict)
        XCTAssertEqual(decision, .skipBelowDaysSinceInstall(observed: 15, required: 30))
    }
}
