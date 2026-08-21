#if canImport(UIKit)
import SwiftUI

enum Theme {
    /// With no brand colour configured the widget borrows the host app's
    /// tint rather than imposing one of its own.
    static let fallbackAccent = Color.accentColor

    /// Messages-style ladder: a plain page with raised surfaces on top.
    /// The grouped ladder washes the whole screen in (242, 242, 247),
    /// which reads as a purple tint at full-screen size.
    static let page = Color(.systemBackground)
    static let surface = Color(.systemGray6)

    /// Brand accent from the project config, falling back to the host tint.
    static func accent(_ config: FeddyConfig?) -> Color {
        guard let hex = config?.brand.color, let color = Color(hex: hex) else {
            return fallbackAccent
        }
        return color
    }

    /// Readable text on a solid accent fill. The brand colour is whatever
    /// hex the developer configured, so a light one needs dark text.
    static func onAccent(_ config: FeddyConfig?) -> Color {
        guard let hex = config?.brand.color,
              let rgb = RGB(hex: hex)
        else {
            return .white
        }
        return rgb.needsDarkText ? .black : .white
    }
}

extension Color {
    init?(hex: String) {
        guard let rgb = RGB(hex: hex) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
#endif
