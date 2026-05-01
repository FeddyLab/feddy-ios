#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

#if canImport(StoreKit)
import StoreKit
#endif

/// Glue layer between ``Feddy/requestReviewIfAppropriate(boardKey:)``
/// and the actual UI. Walks the key window's view-controller chain
/// to find a presentation host, evaluates the rule engine against the
/// store, and either:
///
/// - Presents ``SmartReviewSheet`` and routes the rating outcome
///   (≥4 → system review prompt, ≤3 → ``RequestComposeView``); or
/// - Logs the skip reason from the engine and returns silently.
///
/// `inFlight` is a process-wide latch that prevents the sheet from
/// stacking on itself when the host app calls
/// ``Feddy/requestReviewIfAppropriate(boardKey:)`` from multiple
/// callbacks in quick succession (e.g. a save-success handler that
/// fires twice). The latch releases on every terminal path —
/// dismiss, rating, system review trigger, presentation failure.
@available(iOS 15.0, *)
@MainActor
enum SmartReviewPresenter {
    private static let inFlight = Locked<Bool>(false)

    static func presentIfAppropriate(
        store: SmartReviewStore,
        rules: SmartReviewRules = .default,
        boardKey: String?
    ) {
        let acquired = inFlight.write { wasInFlight -> Bool in
            guard !wasInFlight else { return false }
            wasInFlight = true
            return true
        }
        guard acquired else {
            print("[Feddy] requestReviewIfAppropriate ignored — already presenting")
            return
        }

        let now = Date()
        let decision = SmartReviewEngine.eval(
            now: now,
            state: store.snapshot(),
            rules: rules
        )

        guard case .show = decision else {
            print("[Feddy] Smart Review skipped — \(describe(decision))")
            release()
            return
        }

        guard let presenter = topViewController() else {
            print("[Feddy] Smart Review aborted — no presenting view controller")
            release()
            return
        }

        let sheet = SmartReviewSheet(
            onRated: { stars in
                store.markShown(at: Date())
                if stars >= 4 {
                    triggerSystemReview(from: presenter)
                } else {
                    presentCompose(from: presenter, boardKey: boardKey)
                }
                release()
            },
            onCancel: {
                // Cancel does NOT call markShown — the user never saw
                // the actual review UI, so cooldown / yearly cap stay
                // untouched.
                release()
            }
        )
        let host = UIHostingController(rootView: sheet)
        host.modalPresentationStyle = .formSheet
        if #available(iOS 16.0, *) {
            host.sheetPresentationController?.detents = [.medium()]
            host.sheetPresentationController?.prefersGrabberVisible = true
        }
        presenter.present(host, animated: true)
    }

    static func release() {
        inFlight.write { $0 = false }
    }

    // MARK: - Routing

    private static func triggerSystemReview(from presenter: UIViewController) {
        // Use the scene-bound API rather than the deprecated no-arg
        // form. iOS 18 prefers SwiftUI's `@Environment(\.requestReview)`
        // but the scene API still works there and lets us keep one
        // code path across the SDK's iOS 15+ floor.
        guard let scene = presenter.view.window?.windowScene else {
            print("[Feddy] system review prompt aborted — no window scene")
            return
        }
        #if canImport(StoreKit)
        SKStoreReviewController.requestReview(in: scene)
        #endif
    }

    private static func presentCompose(
        from presenter: UIViewController,
        boardKey: String?
    ) {
        let composeView: RequestComposeView
        if let boardKey, !boardKey.isEmpty {
            // Host pinned a board — single-board mode hides the
            // picker so a frustrated user isn't asked to triage their
            // own complaint.
            composeView = RequestComposeView(
                boards: [FeedbackBoard(key: boardKey, name: boardKey)]
            )
        } else {
            composeView = RequestComposeView()
        }
        let host = UIHostingController(rootView: composeView)
        host.modalPresentationStyle = .formSheet
        // The pre-prompt sheet is still on screen; dismiss it first so
        // the compose sheet has a clear stage. UIKit will animate the
        // dismiss, then present the new sheet on completion.
        presenter.dismiss(animated: true) {
            // Re-resolve the top VC because the prior `presenter`
            // reference was the one we just dismissed away from.
            if let restored = topViewController() {
                restored.present(host, animated: true)
            }
        }
    }

    // MARK: - Top VC discovery

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let activeScene =
            scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        guard let scene = activeScene else { return nil }
        let keyWindow =
            scene.windows.first(where: { $0.isKeyWindow })
            ?? scene.windows.first
        guard var top = keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private static func describe(_ decision: SmartReviewDecision) -> String {
        switch decision {
        case .show:
            return "show"
        case let .skipBelowDaysSinceInstall(observed, required):
            return "below minDaysSinceInstall (\(observed)/\(required))"
        case let .skipBelowSessions(observed, required):
            return "below minSessions (\(observed)/\(required))"
        case let .skipInCooldown(observedDays, requiredDays):
            return "still in cooldown (\(observedDays)d / \(requiredDays)d)"
        case let .skipYearlyCapReached(observed, cap):
            return "yearly cap reached (\(observed)/\(cap))"
        }
    }
}
#endif
