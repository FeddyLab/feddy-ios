import Foundation

public struct FeddyConfiguration: Sendable {
    public let apiKey: String
    public let baseURL: URL

    public static let defaultBaseURL = URL(string: "https://api.feddy.app")!

    public init(apiKey: String, baseURL: URL = FeddyConfiguration.defaultBaseURL) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FeddyError.invalidAPIKey(reason: "Project ID is empty.")
        }
        // Reject server API keys explicitly so a leaked fed_sk_* does not
        // ship inside an iOS binary. Server keys are server-to-server only.
        if trimmed.hasPrefix("fed_sk_") {
            throw FeddyError.invalidAPIKey(
                reason: "Server API keys (fed_sk_*) must not be embedded in clients. Use your Project ID (fed_xxxxxxxxxxxx) instead."
            )
        }
        guard Self.isWellFormedProjectId(trimmed) else {
            throw FeddyError.invalidAPIKey(
                reason: "Invalid Project ID. Expected format: fed_ followed by 12 alphanumeric characters."
            )
        }
        self.apiKey = trimmed
        self.baseURL = baseURL
    }

    private static func isWellFormedProjectId(_ value: String) -> Bool {
        guard value.hasPrefix("fed_") else { return false }
        let body = value.dropFirst(4)
        guard body.count == 12 else { return false }
        return body.allSatisfy { ch in
            ch.isASCII && (ch.isLetter || ch.isNumber)
        }
    }
}
