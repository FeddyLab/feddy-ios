#if canImport(UIKit)
import SwiftUI

/// "Powered by Feddy", set in the page's own text colour so it reads as a
/// signature rather than a hint. No colour and no mark of its own: what it
/// shows is meant to come from the server later, alongside the home blocks.
struct PoweredByFeddy: View {
    private static let url = URL(string: "https://feddy.app/?utm_source=ios-sdk&utm_medium=powered-by")!

    var body: some View {
        Link(destination: Self.url) {
            HStack(spacing: 4) {
                Text("Powered by")
                    .fontWeight(.medium)
                Text("Feddy")
                    .fontWeight(.bold)
            }
            .font(.footnote)
            .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
