import Foundation

/// Threshold bundle the rule engine evaluates against. Kept internal
/// on purpose — host apps have no local override channel; defaults
/// are hard-coded here. A future remote-config layer can hand a
/// non-default `SmartReviewRules` to the engine without changing
/// the public API surface, so this struct's shape is meant to stay
/// stable.
struct SmartReviewRules: Sendable, Equatable {
    /// Minimum days between first SDK sighting and any prompt.
    let minDaysSinceInstall: Int
    /// Minimum cumulative `configure(...)` calls before any prompt.
    let minSessions: Int
    /// Days that must elapse since the last actual show before the
    /// SDK is willing to re-prompt.
    let cooldownDays: Int
    /// Maximum prompts in any rolling 365-day window. Aligned with
    /// Apple's own yearly throttle so we don't burn an opportunity
    /// the system would have silently dropped anyway.
    let yearlyCap: Int

    static let `default` = SmartReviewRules(
        minDaysSinceInstall: 7,
        minSessions: 5,
        cooldownDays: 90,
        yearlyCap: 3
    )
}

/// Outcome of one ``SmartReviewEngine/eval(now:state:rules:)`` call.
/// Carries the failing field plus its observed and required values
/// so the caller can log a useful skip reason without recomputing.
enum SmartReviewDecision: Equatable, Sendable {
    case show
    case skipBelowDaysSinceInstall(observed: Int, required: Int)
    case skipBelowSessions(observed: Int, required: Int)
    case skipInCooldown(observedDays: Int, requiredDays: Int)
    case skipYearlyCapReached(observed: Int, cap: Int)
}

/// Pure-function rule engine. Inputs are a `now` clock value, a
/// snapshot of persisted state, and a rules bundle; output is a
/// `SmartReviewDecision`. No side effects, no I/O — all gating logic
/// lives here so it's trivially unit-testable.
enum SmartReviewEngine {
    static func eval(
        now: Date,
        state: SmartReviewState,
        rules: SmartReviewRules
    ) -> SmartReviewDecision {
        // Gate 1 — install age. Missing install date means the SDK
        // hasn't run `bumpSession` yet, which means 0 days have passed.
        let daysSinceInstall: Int
        if let installDate = state.installDate {
            daysSinceInstall = wholeDays(from: installDate, to: now)
        } else {
            daysSinceInstall = 0
        }
        if daysSinceInstall < rules.minDaysSinceInstall {
            return .skipBelowDaysSinceInstall(
                observed: daysSinceInstall,
                required: rules.minDaysSinceInstall
            )
        }

        // Gate 2 — session count.
        if state.sessionCount < rules.minSessions {
            return .skipBelowSessions(
                observed: state.sessionCount,
                required: rules.minSessions
            )
        }

        // Gate 3 — cooldown since last shown.
        if let lastShownAt = state.lastShownAt {
            let daysSinceLast = wholeDays(from: lastShownAt, to: now)
            if daysSinceLast < rules.cooldownDays {
                return .skipInCooldown(
                    observedDays: daysSinceLast,
                    requiredDays: rules.cooldownDays
                )
            }
        }

        // Gate 4 — yearly cap. Only counts shows still inside the
        // current rolling window; an expired window means the store
        // will reset on the next markShown.
        if let windowStart = state.yearlyWindowStart,
           now.timeIntervalSince(windowStart) < SmartReviewStore.yearlyWindowSeconds,
           state.yearlyCount >= rules.yearlyCap {
            return .skipYearlyCapReached(
                observed: state.yearlyCount,
                cap: rules.yearlyCap
            )
        }

        return .show
    }

    /// Whole 86_400-second days between two timestamps. Floor so
    /// "exactly 7 days minus 1 second" stays at 6 (i.e. the 7-day
    /// gate trips at 7d 0s, not 6d 23h 59m).
    private static func wholeDays(from start: Date, to end: Date) -> Int {
        let elapsed = end.timeIntervalSince(start)
        if elapsed <= 0 { return 0 }
        return Int(elapsed / 86_400)
    }
}
