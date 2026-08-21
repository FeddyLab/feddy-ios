#if canImport(UIKit)
import SwiftUI

enum Theme {
    /// With no brand colour configured the widget borrows the host app's
    /// tint rather than imposing one of its own.
    static let fallbackAccent = Color.accentColor

    /// Brand accent from the project config, falling back to the host tint.
    static func accent(_ config: FeddyConfig?) -> Color {
        guard let hex = config?.brand.color, let color = Color(hex: hex) else {
            return fallbackAccent
        }
        return color
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
#endif
