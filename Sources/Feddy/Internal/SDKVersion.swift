import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Static metadata about the Feddy SDK and its host environment, exposed
/// as HTTP headers on every outbound API call so the server can keep an
/// install census per workspace × app version × sdk version. See
/// `FeddyClient.postRawData` for where these get attached.
enum SDKVersion {
    /// Bumped per release.
    static let current = "0.7.3"

    /// Stable platform identifier sent as `X-Feddy-Sdk-Platform`. Always
    /// "ios" for this SDK regardless of which Apple OS we're actually
    /// running on — the OS distinction is carried in `osName`.
    static let platform = "ios"

    static let deviceManufacturer = "Apple"

    /// Free-form descriptor combining SDK + OS + platform. Sent as
    /// `User-Agent` for legacy log readability; the structured
    /// `X-Feddy-*` headers carry the same data in machine-parseable form.
    static var userAgent: String {
        "Feddy-iOS/\(current) (\(osName))"
    }

    static var osName: String {
        #if os(iOS)
        // iPad on iPadOS still reports `os(iOS)` at compile time but the
        // runtime UIDevice tells us "iPad" → distinguish so dashboards can
        // segment iPad-specific feedback.
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "iPadOS"
        }
        #endif
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "unknown"
        #endif
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.patchVersion == 0 {
            return "\(v.majorVersion).\(v.minorVersion)"
        }
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Hardware identifier from `uname()` — e.g. `iPhone15,2`. On Simulator
    /// this returns `arm64` / `x86_64` (the host arch); we keep that as-is
    /// because "this is a Simulator install" is itself useful telemetry.
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        // Mirror reflects each byte of the C tuple as a child; collect
        // the leading non-zero bytes. Using Mirror sidesteps the
        // exclusivity warning that withUnsafePointer(to:) would trip when
        // reading `info.machine` directly.
        let bytes = Mirror(reflecting: info.machine)
            .children
            .compactMap { $0.value as? Int8 }
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    /// BCP-47-ish locale identifier. `Locale.current.identifier` returns
    /// `en_US` style on most Apple platforms; we replace the underscore so
    /// downstream readers get the more common `en-US` form.
    static var locale: String {
        Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    /// Bundle identifier of the host app — `com.foo.bar`. iOS / macOS use
    /// the same `Bundle.main.bundleIdentifier`. May be nil in unusual host
    /// environments (e.g. some unit-test harnesses); SDK callers treat
    /// absence as "skip the header".
    static var appId: String? {
        Bundle.main.bundleIdentifier
    }

    /// `CFBundleShortVersionString` — the user-facing version like `3.2.1`.
    static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// `CFBundleVersion` — the build number like `432`.
    static var appBuild: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}
