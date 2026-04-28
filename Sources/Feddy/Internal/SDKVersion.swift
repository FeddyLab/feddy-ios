import Foundation

enum SDKVersion {
    static let current = "0.1.0"

    static var userAgent: String {
        let platform: String
        #if os(iOS)
        platform = "iOS"
        #elseif os(macOS)
        platform = "macOS"
        #elseif os(tvOS)
        platform = "tvOS"
        #elseif os(watchOS)
        platform = "watchOS"
        #elseif os(visionOS)
        platform = "visionOS"
        #else
        platform = "unknown"
        #endif
        return "Feddy-iOS/\(current) (\(platform))"
    }
}
