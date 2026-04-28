import Foundation

/// Demo app configuration. The default `apiKey` is a placeholder so
/// the project compiles out of the box; replace it (or set the
/// `FEDDY_API_KEY` environment variable in the Run scheme) with your
/// own `fed_pk_*` key from `dashboard.feddy.app` to route submissions
/// to your own project.
enum DemoConfig {
    static let apiKey: String = {
        let env = ProcessInfo.processInfo.environment["FEDDY_API_KEY"] ?? ""
        return env.isEmpty ? defaultApiKey : env
    }()

    private static let defaultApiKey = "fed_pk_REPLACE_WITH_YOUR_KEY"

    static var isPlaceholder: Bool {
        apiKey == defaultApiKey
    }
}
