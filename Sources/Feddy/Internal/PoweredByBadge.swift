#if canImport(SwiftUI)
import SwiftUI

/// Footer rendered at the bottom of the SDK's feedback views
/// (compose / list / detail / roadmap). Reads the cached branding
/// payload from `CapabilitiesFetcher`:
///
/// - `nil` (Pro / Team workspace) → renders `EmptyView()`.
/// - non-`nil` (Free workspace, or fail-secure default before the
///   first network round-trip) → renders text + optional logo,
///   opens `branding.url` on tap.
///
/// Triggers a background capabilities refresh on appear so a plan
/// change on the dashboard converges within 24 h. The visibility
/// decision is **server-driven** — there is intentionally no local
/// API to hide the badge, because removing the data is the protocol-
/// level fact, not a client toggle.
@available(iOS 15.0, macOS 12.0, *)
struct PoweredByBadge: View {
    @State private var branding: Branding? = nil
    @State private var resolved = false

    var body: some View {
        Group {
            if resolved, let branding {
                badgeBody(branding)
            } else {
                // Either pre-resolution (very brief, single tick) or
                // resolved-to-nil (Pro). Both render to nothing — the
                // surrounding view just sees no footer.
                EmptyView()
            }
        }
        .task {
            branding = CapabilitiesFetcher.currentBranding()
            resolved = true
            if let client = Feddy.currentClientIfReady() {
                CapabilitiesFetcher.refreshInBackground(client: client)
            }
        }
    }

    @ViewBuilder
    private func badgeBody(_ branding: Branding) -> some View {
        if let url = URL(string: branding.url) {
            Link(destination: url) {
                badgeContent(branding)
            }
            .buttonStyle(.plain)
        } else {
            badgeContent(branding)
        }
    }

    private func badgeContent(_ branding: Branding) -> some View {
        HStack(spacing: 6) {
            if let logo = branding.logoUrl, let logoURL = URL(string: logo) {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        Color.clear
                    }
                }
                .frame(width: 14, height: 14)
            }
            Text(branding.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
#endif
