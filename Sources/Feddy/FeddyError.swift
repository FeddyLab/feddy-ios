import Foundation

public enum FeddyError: Error, Equatable, Sendable {
    /// `Feddy.configure(...)` was never called.
    case notConfigured

    /// API key did not start with `pk_live_` or `pk_test_`.
    case invalidAPIKey(reason: String)

    /// Local validation failed before the request was sent.
    case invalidPayload(reason: String)

    /// Underlying URLSession failure (DNS, connectivity, TLS, etc.).
    case network(URLError)

    /// Server responded with a non-2xx status. `code` and `message` mirror
    /// the `{ code, message }` envelope returned by `feddy-api`.
    case http(status: Int, code: String?, message: String?)

    /// Response body did not match the expected schema.
    case decoding(String)
}

extension FeddyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Feddy.configure(with:) must be called before any other API."
        case .invalidAPIKey(let reason):
            return "Invalid Feddy API key: \(reason)"
        case .invalidPayload(let reason):
            return "Invalid Feddy payload: \(reason)"
        case .network(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .http(let status, let code, let message):
            let codePart = code.map { " [\($0)]" } ?? ""
            let messagePart = message.map { ": \($0)" } ?? ""
            return "HTTP \(status)\(codePart)\(messagePart)"
        case .decoding(let detail):
            return "Decoding error: \(detail)"
        }
    }
}
