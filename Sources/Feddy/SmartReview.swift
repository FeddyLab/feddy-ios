import Foundation

extension Feddy {
    /// Ask the SDK to consider showing a Smart Review prompt right
    /// now. Call from any "user just had a good moment" hook —
    /// onboarding completed, save succeeded, level cleared, support
    /// ticket marked resolved, etc. The SDK's built-in gates decide
    /// whether to actually present anything:
    ///
    /// - At least 7 days since the SDK first ran on this install
    /// - At least 5 cumulative `configure` calls
    /// - At least 90 days since the last actual presentation
    /// - At most 3 presentations in any rolling 365-day window
    ///   (matches Apple's own throttle)
    ///
    /// If all gates pass, the SDK shows a 5-star pre-prompt sheet:
    ///
    /// - **≥ 4 stars** → triggers the system review prompt via
    ///   `SKStoreReviewController`. The 5-star App Store action is
    ///   handed to Apple's UI; the SDK never sees the rating the
    ///   user types into the App Store sheet.
    /// - **≤ 3 stars** → presents ``RequestComposeView`` so the
    ///   feedback is captured privately in the host workspace
    ///   instead of as a public 1-3 star App Store review. This is
    ///   the "review shield" — keeps low ratings off the App Store
    ///   and turns them into actionable bug reports.
    ///
    /// Fire-and-forget: returns immediately. No-op if `configure`
    /// has not yet been called or if any gate fails (a console line
    /// describes which gate skipped).
    ///
    /// - Parameters:
    ///   - boardKey: Which dashboard board the low-rating capture
    ///     lands in (same semantics as `boardKey` on
    ///     ``submitRequest(title:description:boardKey:images:)``).
    ///     Omit to fall back to the workspace's default board picker.
    ///   - trigger: Optional caller-defined label that identifies
    ///     where in your app this prompt fired from — e.g.
    ///     `"task_50_complete"` vs `"share_used"`. Surfaces in your
    ///     dashboard funnel so you can compare which moments drive
    ///     the best ratings. Trimmed and capped at 100 characters;
    ///     empty / whitespace-only values are treated as nil.
    @available(iOS 15.0, *)
    @MainActor
    public static func requestReviewIfAppropriate(
        boardKey: String? = nil,
        trigger: String? = nil
    ) {
        #if canImport(UIKit) && canImport(SwiftUI)
        guard let client = currentClientIfReady() else {
            print("[Feddy] requestReviewIfAppropriate called before configure — ignoring")
            return
        }
        SmartReviewPresenter.presentIfAppropriate(
            client: client,
            boardKey: boardKey,
            trigger: normalizeTrigger(trigger)
        )
        #else
        // Smart Review needs UIKit + SwiftUI — silent no-op on
        // platforms that lack either (Linux CI, FoundationOnly).
        _ = boardKey
        _ = trigger
        #endif
    }

    /// Trim, drop empty, cap at 100 chars (matches server's
    /// `z.string().trim().min(1).max(100)` so a misuse on the
    /// client never costs a 400 round-trip).
    private static func normalizeTrigger(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        if trimmed.count <= 100 { return trimmed }
        return String(trimmed.prefix(100))
    }

    /// Clear every persisted Smart Review counter — install date,
    /// session count, last-shown timestamp, yearly counter.
    ///
    /// **Debug menus only.** Calling this in production lets users
    /// see the prompt more often than designed; the production
    /// throttle exists because the App Store itself caps prompts
    /// per year (Apple's count is opaque to apps and is not reset
    /// by this call).
    public static func resetSmartReviewState() {
        guard let client = currentClientIfReady() else {
            print("[Feddy] resetSmartReviewState called before configure — ignoring")
            return
        }
        client.smartReviewStore.clearAll()
        SmartReviewConfigFetcher.clearCache()
    }
}
