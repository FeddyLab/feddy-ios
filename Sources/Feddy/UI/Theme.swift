#if canImport(UIKit)
import SwiftUI
import UIKit

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
        guard let rgb = accentComponents(config) else { return .white }
        return rgb.needsDarkText ? .black : .white
    }

    /// The contact's own bubble. Deliberately fixed rather than derived
    /// from the brand colour: the widget sits inside someone else's app,
    /// and a large tinted surface reads as a claim about that app.
    static let ownBubble = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.17, blue: 0.26, alpha: 1)
            : UIColor(red: 0.91, green: 0.94, blue: 0.99, alpha: 1)
    })

    /// The configured hex when there is one, otherwise whatever the host
    /// app's tint resolves to right now.
    private static func accentComponents(_ config: FeddyConfig?) -> RGB? {
        if let hex = config?.brand.color, let rgb = RGB(hex: hex) {
            return rgb
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(fallbackAccent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        else {
            return nil
        }
        return RGB(hex: String(
            format: "%02X%02X%02X",
            Int(red * 255), Int(green * 255), Int(blue * 255)
        ))
    }
}

extension Color {
    init?(hex: String) {
        guard let rgb = RGB(hex: hex) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
#endif
