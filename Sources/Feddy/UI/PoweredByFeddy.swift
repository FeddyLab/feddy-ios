#if canImport(UIKit)
import SwiftUI

/// "Powered by Feddy", set in the page's own text colour so it reads as a
/// signature rather than a hint. No colour and no mark of its own: what it
/// shows is meant to come from the server later, alongside the home blocks.
struct PoweredByFeddy: View {
    private static let url = URL(string: "https://feddy.app/?utm_source=ios-sdk&utm_medium=powered-by")!
    @Environment(\.openURL) private var openURL

    // A plain button, not a Link: Link paints its label in the accent
    // colour and a foregroundStyle inside it does not win.
    var body: some View {
        Button { openURL(Self.url) } label: {
            HStack(spacing: 4) {
                Text("Powered by")
                    .fontWeight(.medium)
                Text("Feddy")
                    .fontWeight(.bold)
            }
            .font(.footnote)
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
#endif
