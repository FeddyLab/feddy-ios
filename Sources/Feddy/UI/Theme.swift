#if canImport(UIKit)
import SwiftUI
import UIKit

enum Theme {
    /// With no brand colour configured the widget borrows the host app's
    /// tint rather than imposing one of its own.
    static let fallbackAccent = Color.accentColor

    /// Messages-style ladder: a plain page with raised surfaces on top.
    /// The grouped ladder washes the whole screen in (242, 242, 247),
    /// which reads as a purple tint at full-screen size — one more reason
    /// the surfaces above are fills rather than greys.
    static let page = Color(.systemBackground)

    /// Raised surfaces: inputs, chips, and the teammate's bubbles. Apple
    /// documents this fill for exactly these shapes ("input fields, search
    /// bars, or buttons"), and the fill palette is translucent by design,
    /// so it keeps its contrast in the elevated trait context a sheet
    /// renders in — which is where the grey *background* colours collapse
    /// into the page and every surface loses its edge.
    static let surface = Color(.tertiarySystemFill)

    /// Rules that separate regions — never an outline around a control.
    /// Filled surfaces carry their own edge, the way the system's own
    /// chips and search fields do.
    static let hairline = Color(.separator)

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

    /// The contact's own bubble: one step heavier than `surface`, so the
    /// two sides of a thread read apart without either being tinted.
    /// Deliberately not the brand colour — the panel sits inside someone
    /// else's app, and a large tinted surface reads as a claim about it.
    static let ownBubble = Color(.secondarySystemFill)

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
