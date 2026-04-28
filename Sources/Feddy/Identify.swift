import Foundation

extension Feddy {
    /// Profile attribute value supported by `/v1/identify`'s `profile`
    /// blob. Mirrors what the server stores per user.
    public enum ProfileValue: Sendable, Encodable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }
    }
}

extension FeddyClient {
    @available(iOS 15.0, macOS 12.0, *)
    func identify(
        externalUserId: String?,
        email: String?,
        displayName: String?,
        avatarURL: URL?,
        profile: [String: Feddy.ProfileValue]?
    ) async throws {
        let body = IdentifyRequestBody(
            externalUserId: externalUserId,
            anonymousToken: externalUserId == nil ? anonymousToken : nil,
            email: email,
            displayName: displayName,
            avatarURL: avatarURL?.absoluteString,
            profile: profile
        )
        _ = try await postRaw(path: "/v1/identify", body: body)
    }
}

private struct IdentifyRequestBody: Encodable {
    let externalUserId: String?
    let anonymousToken: String?
    let email: String?
    let displayName: String?
    let avatarURL: String?
    let profile: [String: Feddy.ProfileValue]?

    enum CodingKeys: String, CodingKey {
        case externalUserId = "external_user_id"
        case anonymousToken = "anonymous_token"
        case email
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case profile
    }
}
