import Foundation

public struct FeddyConfiguration: Sendable {
    public let apiKey: String
    public let baseURL: URL

    public static let defaultBaseURL = URL(string: "https://api.feddy.app")!

    public init(apiKey: String, baseURL: URL = FeddyConfiguration.defaultBaseURL) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FeddyError.invalidAPIKey(reason: "API key is empty.")
        }
        // Reject secret keys explicitly so a leaked `fed_sk_*` does not ship
        // inside an iOS binary. Secret keys are server-to-server only.
        if trimmed.hasPrefix("fed_sk_") {
            throw FeddyError.invalidAPIKey(
                reason: "Secret keys (fed_sk_*) must not be used in clients. Use the project's publishable key (fed_pk_*)."
            )
        }
        guard trimmed.hasPrefix("fed_pk_") else {
            throw FeddyError.invalidAPIKey(
                reason: "API key must start with 'fed_pk_'."
            )
        }
        self.apiKey = trimmed
        self.baseURL = baseURL
    }
}
