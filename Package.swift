// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Feddy",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        // Keeps `swift build` / `swift test` working on a Mac host; the
        // UI compiles only where UIKit is available.
        .macOS(.v12),
    ],
    products: [
        .library(name: "Feddy", targets: ["Feddy"])
    ],
    targets: [
        .target(
            name: "Feddy",
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "FeddyTests",
            dependencies: ["Feddy"]
        ),
    ]
)
