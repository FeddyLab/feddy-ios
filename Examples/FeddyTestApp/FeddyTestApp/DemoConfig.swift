import Foundation

/// Demo app configuration. The Project ID is read **only** from the
/// `FEDDY_API_KEY` environment variable on the Xcode Run scheme — it is
/// never stored in source so contributors don't accidentally commit a
/// real ID into the public SDK repository.
///
/// Set yours from:
///   Product → Scheme → Edit Scheme → Run → Arguments →
///   Environment Variables → `FEDDY_API_KEY = fed_xxxxxxxxxxxx`
///
/// Without it, the app shows a "Set FEDDY_API_KEY" empty state instead
/// of crashing or sending writes to nowhere.
enum DemoConfig {
    static let apiKey: String = {
        let value = ProcessInfo.processInfo.environment["FEDDY_API_KEY"] ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// `true` when no `FEDDY_API_KEY` env var was provided. Drives the
    /// demo's onboarding empty state.
    static var isPlaceholder: Bool {
        apiKey.isEmpty
    }
}
