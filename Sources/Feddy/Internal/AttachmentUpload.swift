import Foundation

/// Two-step attachment upload against `feddy-api`:
///
/// 1. `POST /v1/attachments/sign` — server returns an HMAC-signed
///    upload ticket (URL + key + ttl). Premium-gate happens here:
///    non-premium workspaces get `feature_not_available` and the
///    SDK should never have called this in the first place (entry
///    UI is hidden).
/// 2. `PUT /v1/attachments/upload?ticket=...` — raw bytes streamed
///    to R2. Content-Type header must match the ticket; we always
///    send `image/jpeg` since `ImageCompression` produces JPEG.
///
/// Caller (`SubmitRequest.swift`) collects the returned `key`s and
/// passes them in `attachment_keys` on `POST /v1/requests`.
extension FeddyClient {
    @available(iOS 15.0, macOS 12.0, *)
    func uploadAttachment(jpeg: Data) async throws -> String {
        let ticket = try await signAttachment(
            contentType: "image/jpeg",
            size: jpeg.count
        )
        try await putAttachmentBytes(
            uploadPath: ticket.uploadURL,
            contentType: "image/jpeg",
            body: jpeg
        )
        return ticket.key
    }

    @available(iOS 15.0, macOS 12.0, *)
    private func signAttachment(
        contentType: String,
        size: Int
    ) async throws -> AttachmentSignResponse {
        let body = AttachmentSignBody(contentType: contentType, size: size)
        return try await post(
            path: "/v1/attachments/sign",
            body: body,
            responseType: AttachmentSignResponse.self
        )
    }

    @available(iOS 15.0, macOS 12.0, *)
    private func putAttachmentBytes(
        uploadPath: String,
        contentType: String,
        body: Data
    ) async throws {
        // Ticket-bearing path is relative ("/v1/attachments/upload?ticket=...");
        // resolve against the configured base.
        guard let url = URL(string: uploadPath, relativeTo: configuration.baseURL)
        else {
            throw FeddyError.invalidPayload(reason: "Could not build upload URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw FeddyError.network(urlError)
        } catch {
            throw FeddyError.network(URLError(.unknown))
        }

        guard let http = response as? HTTPURLResponse else {
            throw FeddyError.http(status: -1, code: nil, message: "Non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            // Reuse the api error envelope shape.
            struct Envelope: Decodable {
                let code: String?
                let message: String?
            }
            let envelope = try? JSONDecoder.feddy.decode(Envelope.self, from: data)
            throw FeddyError.http(
                status: http.statusCode,
                code: envelope?.code,
                message: envelope?.message
            )
        }
    }
}

private struct AttachmentSignBody: Encodable {
    let contentType: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case size
    }
}

private struct AttachmentSignResponse: Decodable {
    let uploadURL: String
    let assetURL: String
    let key: String

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case assetURL = "asset_url"
        case key
    }
}
