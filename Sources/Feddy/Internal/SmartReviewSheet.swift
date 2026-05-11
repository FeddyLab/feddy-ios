#if canImport(SwiftUI)
import SwiftUI

/// Pre-prompt sheet shown by ``SmartReviewPresenter``. Two-step
/// like / dislike confirmation that replaces the legacy 5-star UI:
///
/// 1. Asks "Enjoying this app?" with two buttons.
/// 2. If the user likes the app, a second confirmation asks whether
///    they want to rate now. Tapping the affirmative call-to-action
///    is what triggers `SKStoreReviewController` — this guards
///    Apple's three-per-year quota against users who picked "like"
///    but aren't actually about to rate.
///
/// Five terminal callbacks; exactly one fires before the sheet
/// dismisses:
///
/// - `onLiked` — step 1 like, NOT terminal. Sheet transitions to
///   step 2 internally; the presenter uses this to record the
///   `liked` funnel event and engagement (cooldown bookkeeping).
/// - `onDisliked` — step 1 dislike, terminal. Presenter opens the
///   feedback composer.
/// - `onStoreConfirmed` — step 2 confirm, terminal. Presenter
///   actually calls `SKStoreReviewController`.
/// - `onStoreDismissed` — step 2 "Not now" or drag-away, terminal.
///   Presenter logs `dismissed_store_confirm`.
/// - `onSheetDismissedBeforeChoice` — drag-away with no step-1
///   selection, terminal. Presenter logs `dismissed`.
@available(iOS 15.0, macOS 12.0, *)
struct SmartReviewSheet: View {
    let onLiked: () -> Void
    let onDisliked: () -> Void
    let onStoreConfirmed: () -> Void
    let onStoreDismissed: () -> Void
    let onSheetDismissedBeforeChoice: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .step1
    @State private var firedTerminal: Bool = false

    private enum Step { case step1, step2 }

    var body: some View {
        Group {
            switch step {
            case .step1: step1View
            case .step2: step2View
            }
        }
        .onDisappear {
            // Sheet removed without a terminal button tap (drag-away).
            // Pick the correct "no" path based on which step we were
            // on at the moment of dismissal.
            guard !firedTerminal else { return }
            firedTerminal = true
            switch step {
            case .step1:
                onSheetDismissedBeforeChoice()
            case .step2:
                onStoreDismissed()
            }
        }
    }

    private var step1View: some View {
        VStack(spacing: 20) {
            Text(Localization.string("feddy.smartReview.step1.title"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text(Localization.string("feddy.smartReview.step1.subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    guard !firedTerminal else { return }
                    firedTerminal = true
                    onDisliked()
                    dismiss()
                } label: {
                    Text(Localization.string("feddy.smartReview.step1.dislike"))
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    // Non-terminal — transition to step 2 without
                    // dismissing the sheet.
                    onLiked()
                    step = .step2
                } label: {
                    Text(Localization.string("feddy.smartReview.step1.like"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 8)
        }
        .padding(24)
    }

    private var step2View: some View {
        VStack(spacing: 20) {
            Text(Localization.string("feddy.smartReview.step2.title"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text(Localization.string("feddy.smartReview.step2.subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    guard !firedTerminal else { return }
                    firedTerminal = true
                    onStoreDismissed()
                    dismiss()
                } label: {
                    Text(Localization.string("feddy.smartReview.step2.dismiss"))
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    guard !firedTerminal else { return }
                    firedTerminal = true
                    onStoreConfirmed()
                    dismiss()
                } label: {
                    Text(Localization.string("feddy.smartReview.step2.confirm"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 8)
        }
        .padding(24)
    }
}
#endif
