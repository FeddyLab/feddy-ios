// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Feddy",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "Feddy", targets: ["Feddy"]),
    ],
    targets: [
        .target(
            name: "Feddy",
            path: "Sources/Feddy",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "FeddyTests",
            dependencies: ["Feddy"],
            path: "Tests/FeddyTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
