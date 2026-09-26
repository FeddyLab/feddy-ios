#if canImport(UIKit)
import SwiftUI

/// "Powered by Feddy" with the Feddy mark, set in the page's own text
/// colour so it reads as a signature rather than a hint. The mark is the
/// one place the SDK draws Feddy's colour: it is a logo, not UI.
struct PoweredByFeddy: View {
    private static let url = URL(string: "https://feddy.app/?utm_source=ios-sdk&utm_medium=powered-by")!
    @ScaledMetric(relativeTo: .footnote) private var markSize: CGFloat = 16

    var body: some View {
        Link(destination: Self.url) {
            HStack(spacing: 5) {
                Text("Powered by")
                    .fontWeight(.medium)
                FeddyMark()
                    .frame(width: markSize, height: markSize)
                    .padding(.leading, 2)
                Text("Feddy")
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Powered by Feddy")
    }
}

/// The favicon: a rounded brand square with the one-stroke F, drawn from
/// the same 1024-unit artwork (`rx 100`) so it matches everywhere else.
private struct FeddyMark: View {
    private static let brand = Color(red: 0x4F / 255, green: 0x5A / 255, blue: 0xFA / 255)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 100 / 1024, style: .continuous)
                    .fill(Self.brand)
                FeddyF().fill(Color.white)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

private struct FeddyF: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 1024
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var p = Path()
        p.move(to: pt(546.313, 877.861))
        p.addCurve(to: pt(546.293, 877.859), control1: pt(546.309, 877.853), control2: pt(546.298, 877.853))
        p.addCurve(to: pt(513.044, 866.353), control1: pt(535.361, 891.751), control2: pt(513.044, 884.012))
        p.addLine(to: pt(513.044, 696.728))
        p.addCurve(to: pt(510.219, 682.471), control1: pt(513.048, 691.836), control2: pt(512.088, 686.991))
        p.addCurve(to: pt(502.15, 670.385), control1: pt(508.349, 677.951), control2: pt(505.607, 673.844))
        p.addCurve(to: pt(490.068, 662.313), control1: pt(498.692, 666.926), control2: pt(494.586, 664.183))
        p.addCurve(to: pt(475.816, 659.487), control1: pt(485.549, 660.443), control2: pt(480.706, 659.483))
        p.addLine(to: pt(288.594, 659.487))
        p.addCurve(to: pt(273.453, 630.05), control1: pt(273.453, 659.487), control2: pt(264.631, 642.365))
        p.addLine(to: pt(396.556, 457.659))
        p.addCurve(to: pt(366.241, 398.752), control1: pt(414.166, 433.013), control2: pt(396.556, 398.752))
        p.addLine(to: pt(139.652, 398.752))
        p.addCurve(to: pt(124.51, 369.315), control1: pt(124.51, 398.752), control2: pt(115.689, 381.629))
        p.addLine(to: pt(284.084, 145.804))
        p.addCurve(to: pt(299.225, 138), control1: pt(287.606, 140.914), control2: pt(293.235, 138))
        p.addLine(to: pt(774.754, 138))
        p.addCurve(to: pt(789.895, 167.437), control1: pt(789.895, 138), control2: pt(798.716, 155.122))
        p.addLine(to: pt(666.791, 339.828))
        p.addCurve(to: pt(697.106, 398.752), control1: pt(649.182, 364.491), control2: pt(666.791, 398.752))
        p.addLine(to: pt(884.346, 398.752))
        p.addCurve(to: pt(898.993, 428.88), control1: pt(899.865, 398.752), control2: pt(908.588, 416.664))
        p.addLine(to: pt(546.332, 877.863))
        p.addCurve(to: pt(546.313, 877.861), control1: pt(546.327, 877.87), control2: pt(546.317, 877.869))
        p.closeSubpath()
        return p
    }
}
#endif
