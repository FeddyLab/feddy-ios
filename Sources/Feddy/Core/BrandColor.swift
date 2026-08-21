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
    var needsDarkText: Bool { luminance > 0.6 }

    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        let delta = high - low
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = lightness > 0.5
            ? delta / (2 - high - low)
            : delta / (high + low)
        var hue: Double
        if high == red {
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        } else if high == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        return (hue / 6, saturation, lightness)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        guard saturation > 0 else {
            self.init(white: lightness)
            return
        }
        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func component(_ offset: Double) -> Double {
            var t = hue + offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        self.init(
            red: component(1 / 3),
            green: component(0),
            blue: component(-1 / 3)
        )
    }

    init(white: Double) {
        self.init(red: white, green: white, blue: white)
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Same hue, normalised lightness. A fixed alpha cannot do this: 15%
    /// of yellow on white is invisible while 15% of navy is muddy grey.
    func normalisedLightness(_ lightness: Double, maxSaturation: Double) -> RGB {
        let (hue, saturation, _) = hsl
        return RGB(
            hue: hue,
            saturation: min(saturation, maxSaturation),
            lightness: lightness
        )
    }
}
