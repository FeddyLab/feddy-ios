#if canImport(UIKit) && canImport(StoreKit)
import StoreKit
import UIKit

/// Direct path: jump straight to `SKStoreReviewController` without
/// the like / dislike pre-prompt sheet. Host decides when this is
/// appropriate (e.g. immediately after a paywall conversion).
///
/// Deliberately does not consult or update `SmartReviewStore` — the
/// 7-day / 5-session / 90-day-cooldown / 3-per-year gates belong to
/// the shield flow only. Apple's own opaque per-app yearly cap still
/// applies here, so spamming this API across many triggers is not
/// useful; that judgement is on the host.
@available(iOS 15.0, *)
@MainActor
enum SystemDirectReviewPresenter {
    static func present(client: FeddyClient, trigger: String?) {
        guard let scene = activeWindowScene() else {
            print("[Feddy] system-direct review aborted — no window scene")
            return
        }
        SKStoreReviewController.requestReview(in: scene)
        ReviewPromptEventLogger.log(
            stage: .systemDirect,
            trigger: trigger,
            client: client
        )
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
    }
}
#endif
