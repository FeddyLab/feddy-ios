import Foundation

/// Snapshot of every persisted value the rule engine needs to decide
/// whether to actually present a review prompt. Pure value type so
/// ``SmartReviewEngine`` stays trivially testable — pass one in, get
/// a `Decision` back.
struct SmartReviewState: Sendable, Equatable {
    let installDate: Date?
    let sessionCount: Int
    let lastShownAt: Date?
    let yearlyCount: Int
    let yearlyWindowStart: Date?
}

/// UserDefaults-backed state for Smart Review gating. Five keys:
///
/// - `installDate` — first time the SDK saw this install (configure
///   or `requestReviewIfAppropriate`, whichever fires first). The
///   SDK's notion of "install" deliberately equals "integration
///   first runs" so an app that adds Feddy to an already-shipped
///   build doesn't immediately satisfy `minDaysSinceInstall`.
///
/// - `sessionCount` — incremented once per `Feddy.configure(...)`
///   call. Foreground notifications are intentionally not used;
///   30-second lock-screen round trips would inflate the count.
///
/// - `lastShownAt` — bumped any time the SDK actually presented the
///   prompt, regardless of which path the user took (system review
///   vs private capture). Cancel from the pre-prompt sheet does not
///   bump it — the user never saw the actual review UI.
///
/// - `yearlyCount` / `yearlyWindowStart` — rolling 365-day counter so
///   the SDK never exceeds Apple's own yearly throttle. Window
///   resets on first `markShown` after the prior window's end.
struct SmartReviewStore: @unchecked Sendable {
    static let installDateKey = "app.feddy.smartReview.installDate"
    static let sessionCountKey = "app.feddy.smartReview.sessionCount"
    static let lastShownAtKey = "app.feddy.smartReview.lastShownAt"
    static let yearlyCountKey = "app.feddy.smartReview.yearlyCount"
    static let yearlyWindowStartKey = "app.feddy.smartReview.yearlyWindowStart"

    /// Seconds in 365 days. Used for yearly-window rollover; not a
    /// calendar year so leap-year drift can't turn a 4th prompt into
    /// "365 days minus a few hours" by accident.
    static let yearlyWindowSeconds: TimeInterval = 365 * 24 * 60 * 60

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records one session. Lazily writes `installDate` on first
    /// call so a fresh integration starts the gating clock from
    /// today rather than from `Bundle` creation (which on an old
    /// app could already be years past `minDaysSinceInstall`).
    func bumpSession(now: Date = Date()) {
        if defaults.object(forKey: Self.installDateKey) as? Date == nil {
            defaults.set(now, forKey: Self.installDateKey)
        }
        let next = defaults.integer(forKey: Self.sessionCountKey) + 1
        defaults.set(next, forKey: Self.sessionCountKey)
    }

    /// Records that the prompt was actually shown. Updates
    /// `lastShownAt`, increments the yearly counter, and rolls the
    /// 365-day window over when it has fully elapsed.
    func markShown(at now: Date = Date()) {
        defaults.set(now, forKey: Self.lastShownAtKey)

        let windowStart = defaults.object(forKey: Self.yearlyWindowStartKey) as? Date
        if let start = windowStart,
           now.timeIntervalSince(start) < Self.yearlyWindowSeconds {
            // Same rolling window — increment in place.
            let next = defaults.integer(forKey: Self.yearlyCountKey) + 1
            defaults.set(next, forKey: Self.yearlyCountKey)
        } else {
            // Either first show ever, or the previous window has
            // fully elapsed — reset to a new window.
            defaults.set(now, forKey: Self.yearlyWindowStartKey)
            defaults.set(1, forKey: Self.yearlyCountKey)
        }
    }

    /// Snapshot of all five fields for the engine. Reads in one pass
    /// so eval doesn't see a torn state if a write lands mid-call.
    func snapshot() -> SmartReviewState {
        SmartReviewState(
            installDate: defaults.object(forKey: Self.installDateKey) as? Date,
            sessionCount: defaults.integer(forKey: Self.sessionCountKey),
            lastShownAt: defaults.object(forKey: Self.lastShownAtKey) as? Date,
            yearlyCount: defaults.integer(forKey: Self.yearlyCountKey),
            yearlyWindowStart: defaults.object(forKey: Self.yearlyWindowStartKey) as? Date
        )
    }

    /// Wipes every key. Backs ``Feddy/resetSmartReviewState()`` for
    /// debug menus; must not be called in production.
    func clearAll() {
        defaults.removeObject(forKey: Self.installDateKey)
        defaults.removeObject(forKey: Self.sessionCountKey)
        defaults.removeObject(forKey: Self.lastShownAtKey)
        defaults.removeObject(forKey: Self.yearlyCountKey)
        defaults.removeObject(forKey: Self.yearlyWindowStartKey)
    }
}
