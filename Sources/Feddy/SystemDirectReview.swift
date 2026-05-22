import Foundation

extension Feddy {
    /// Bypass the Smart Review shield and invoke
    /// `SKStoreReviewController` immediately. Use this for moments
    /// where the host has already decided the user is happy — e.g.
    /// the instant a paywall purchase succeeds, or a long-running
    /// task the user explicitly waited for completes successfully.
    ///
    /// Difference from ``requestReviewIfAppropriate(boardKey:trigger:)``:
    ///
    /// - **No like / dislike pre-prompt**. The native system sheet
    ///   appears (if Apple decides to show it — the per-app yearly
    ///   cap is opaque to apps and still applies).
    /// - **No private feedback capture** for users who would have
    ///   tapped "not really". Only call this when the host's signal
    ///   that the user is happy is strong; for low-confidence
    ///   moments the shield is the safer default.
    /// - **No SDK-side gates**. The 7-day / 5-session / 90-day
    ///   cooldown / 3-per-year limits exist on the shield path to
    ///   protect users who haven't formed an opinion yet; bypassing
    ///   them is the host's choice.
    ///
    /// Telemetry: a single `stage = "system_direct"` event is
    /// reported to the dashboard funnel with the supplied trigger,
    /// so the host can compare the conversion of this path against
    /// shield-flow triggers.
    ///
    /// Fire-and-forget: returns immediately. No-op if `configure`
    /// has not yet been called.
    ///
    /// - Parameter trigger: Optional caller-defined label that
    ///   identifies where in your app this prompt fired from — e.g.
    ///   `"paywall_purchase_success"` or `"long_export_finished"`.
    ///   Surfaces in your dashboard funnel. Trimmed and capped at
    ///   100 characters; empty / whitespace-only values are treated
    ///   as nil.
    @available(iOS 15.0, *)
    @MainActor
    public static func requestSystemReviewDirect(
        trigger: String? = nil
    ) {
        #if canImport(UIKit) && canImport(StoreKit)
        guard let client = currentClientIfReady() else {
            print("[Feddy] requestSystemReviewDirect called before configure — ignoring")
            return
        }
        SystemDirectReviewPresenter.present(
            client: client,
            trigger: normalizeSystemDirectTrigger(trigger)
        )
        #else
        // SKStoreReviewController needs UIKit + StoreKit — silent
        // no-op on platforms that lack either.
        _ = trigger
        #endif
    }

    /// Trim, drop empty, cap at 100 chars (matches server's
    /// `z.string().trim().min(1).max(100)` so a misuse on the
    /// client never costs a 400 round-trip).
    private static func normalizeSystemDirectTrigger(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        if trimmed.count <= 100 { return trimmed }
        return String(trimmed.prefix(100))
    }
}
