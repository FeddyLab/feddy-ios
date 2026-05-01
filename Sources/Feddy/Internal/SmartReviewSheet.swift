#if canImport(SwiftUI)
import SwiftUI

/// Pre-prompt sheet shown by ``SmartReviewPresenter``. Five star
/// buttons in a row plus a "Not now" dismiss action. Deliberately
/// small and unbranded — the sheet is supposed to feel like a
/// system-style confirmation, not a Feddy-branded modal, so the host
/// app's UI doesn't suddenly carry the SDK's identity at the most
/// sensitive moment in the user journey.
///
/// The two callbacks are mutually exclusive — one always fires
/// before the sheet dismisses:
///
/// - `onRated(stars)` for a 1...5 selection.
/// - `onCancel()` if the user taps Not now or drags the sheet away.
@available(iOS 15.0, macOS 12.0, *)
struct SmartReviewSheet: View {
    let onRated: (Int) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var didFire: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text(Localization.string("feddy.smartReview.prompt.title"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text(Localization.string("feddy.smartReview.prompt.subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        guard !didFire else { return }
                        didFire = true
                        onRated(star)
                        dismiss()
                    } label: {
                        Image(systemName: "star")
                            .font(.system(size: 36, weight: .regular))
                            .foregroundColor(.accentColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(
                            format: Localization.string("feddy.smartReview.star.a11y"),
                            star
                        )
                    )
                }
            }
            .padding(.vertical, 4)

            Button {
                guard !didFire else { return }
                didFire = true
                onCancel()
                dismiss()
            } label: {
                Text(Localization.string("feddy.smartReview.prompt.cancel"))
                    .font(.body)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(24)
        .onDisappear {
            // Sheet was dismissed without picking a star or tapping
            // Not now (drag-away). Treat as cancel so the presenter
            // can release its in-flight latch.
            if !didFire {
                didFire = true
                onCancel()
            }
        }
    }
}
#endif
