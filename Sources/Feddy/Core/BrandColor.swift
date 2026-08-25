import Foundation

/// Parsed sRGB components of a configured brand colour. Kept free of
/// UIKit so the contrast rule can be tested on any platform.
struct RGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let raw = UInt64(value, radix: 16) else { return nil }
        red = Double((raw >> 16) & 0xFF) / 255
        green = Double((raw >> 8) & 0xFF) / 255
        blue = Double(raw & 0xFF) / 255
    }

    /// Relative luminance (WCAG), used only to pick black or white text.
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// A light brand colour needs dark text on top of it.
    ///
    /// Measured as the contrast white would actually get, not as a luminance
    /// cut: at any fixed cut the mid-bright hues still come out white at about
    /// 2.2:1, which cannot be read. 3:1 is what WCAG asks of a UI component
    /// and roughly where the system's own filled buttons sit.
    var needsDarkText: Bool { 1.05 / (luminance + 0.05) < 3 }
}
