import Foundation

extension FeddyClient {
    @available(iOS 15.0, macOS 12.0, *)
    func identify(
        externalUserId: String?,
        email: String?,
        displayName: String?,
        avatarURL: URL?
    ) async throws {
        let body = IdentifyRequestBody(
            externalUserId: externalUserId,
            anonymousToken: externalUserId == nil ? anonymousToken : nil,
            email: email,
            displayName: displayName,
            avatarURL: avatarURL?.absoluteString,
            subscription: subscriptionStore.effective.map(SubscriptionPayload.init)
        )
        // Persist the userId before the network call so a queued
        // submitRequest replay after a process restart still attributes
        // correctly even if the network call below fails.
        identityStore.setLastExternalUserId(externalUserId)
        let response = try await post(
            path: "/v1/identify",
            body: body,
            responseType: IdentifyResponse.self
        )
        identityStore.setAttachmentsEnabled(response.attachmentsEnabled)
    }
}

private struct IdentifyRequestBody: Encodable {
    let externalUserId: String?
    let anonymousToken: String?
    let email: String?
    let displayName: String?
    let avatarURL: String?
    let subscription: SubscriptionPayload?

    enum CodingKeys: String, CodingKey {
        case externalUserId = "external_user_id"
        case anonymousToken = "anonymous_token"
        case email
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case subscription
    }
}

private struct SubscriptionPayload: Encodable {
    let isPaid: Bool
    let status: String
    let productId: String?
    let expiresAt: String?

    init(from subscription: Feddy.Subscription) {
        self.isPaid = subscription.isPaid
        self.status = subscription.status.rawValue
        self.productId = subscription.productId
        self.expiresAt = subscription.expiresAt.map { Self.iso8601.string(from: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case isPaid = "is_paid"
        case status
        case productId = "product_id"
        case expiresAt = "expires_at"
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

private struct IdentifyResponse: Decodable {
    let attachmentsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case attachmentsEnabled = "attachments_enabled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Default to `false` when the server doesn't include the field —
        // mirrors the conservative "hide attachment UI until premium is
        // explicitly confirmed" stance and lets older / cached server
        // responses decode cleanly.
        self.attachmentsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .attachmentsEnabled) ?? false
    }
}
