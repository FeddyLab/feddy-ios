import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DeviceContext {
    static let sdkVersion = "0.6.0"

    /// Context keys for platform "ios" (server renders them by a fixed
    /// key order; unknown keys are listed verbatim).
    static func build() -> [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        var context: [String: String] = [
            "app_version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "device_model": modelIdentifier(),
            "locale": Locale.preferredLanguages.first ?? Locale.current.identifier,
            "sdk_version": sdkVersion,
        ]
        #if canImport(UIKit)
        context["os_version"] = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        context["os_version"] = "macOS \(version.majorVersion).\(version.minorVersion)"
        #endif
        return context
    }

    static func modelIdentifier() -> String {
        // uname() reports the host architecture under the simulator, so
        // prefer the simulated device when one is set.
        let environment = ProcessInfo.processInfo.environment
        if let simulated = environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }
}
