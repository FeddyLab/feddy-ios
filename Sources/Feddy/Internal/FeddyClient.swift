import Foundation

/// Performs HTTP requests against `feddy-api`. One instance per `configure`
/// call; held via `Feddy`'s lock-guarded state.
actor FeddyClient {
    nonisolated let configuration: FeddyConfiguration
    nonisolated let session: URLSession
    nonisolated let identityStore: IdentityStore
    nonisolated let requestQueue: RequestQueue
    nonisolated let subscriptionStore: SubscriptionStore
    nonisolated let smartReviewStore: SmartReviewStore

    init(
        configuration: FeddyConfiguration,
        session: URLSession = .shared,
        identityStore: IdentityStore = IdentityStore(),
        requestQueue: RequestQueue = RequestQueue(),
        subscriptionStore: SubscriptionStore = SubscriptionStore(),
        smartReviewStore: SmartReviewStore = SmartReviewStore()
    ) {
        self.configuration = configuration
        self.session = session
        self.identityStore = identityStore
        self.requestQueue = requestQueue
        self.subscriptionStore = subscriptionStore
        self.smartReviewStore = smartReviewStore
    }

    nonisolated var anonymousToken: String {
        identityStore.tokenOrCreate()
    }

    nonisolated var lastExternalUserId: String? {
        identityStore.lastExternalUserId
    }

    @available(iOS 15.0, macOS 12.0, *)
    func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response {
        let data = try await postRaw(path: path, body: body)
        do {
            return try JSONDecoder.feddy.decode(Response.self, from: data)
        } catch {
            throw FeddyError.decoding(String(describing: error))
        }
    }

    @available(iOS 15.0, macOS 12.0, *)
    func postRaw<Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Data {
        let encoded: Data
        do {
            encoded = try JSONEncoder.feddy.encode(body)
        } catch {
            throw FeddyError.invalidPayload(reason: String(describing: error))
        }
        return try await postRawData(path: path, encodedBody: encoded)
    }

    /// Lower-level POST that takes already-encoded JSON bytes. Used by
    /// the offline-queue replay path where the body was serialized once
    /// at enqueue time and shouldn't be re-encoded on every retry.
    @available(iOS 15.0, macOS 12.0, *)
    func postRawData(
        path: String,
        encodedBody: Data
    ) async throws -> Data {
        let url = configuration.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyStandardHeaders(to: &request)
        request.httpBody = encodedBody
        return try await execute(request)
    }

    /// GET helper for read-side endpoints (list / detail / comments).
    /// Query params get URL-encoded; missing optional values are skipped
    /// rather than sent as empty strings (mirrors how the server's zod
    /// `.optional()` expects fields to be absent, not blank).
    @available(iOS 15.0, macOS 12.0, *)
    func get<Response: Decodable>(
        path: String,
        query: [String: String?] = [:]
    ) async throws -> Response {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.compactMap { key, value in
                guard let value, !value.isEmpty else { return nil }
                return URLQueryItem(name: key, value: value)
            }
        }
        guard let url = components?.url else {
            throw FeddyError.invalidPayload(reason: "Could not build URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyStandardHeaders(to: &request)
        let data = try await execute(request)
        do {
            return try JSONDecoder.feddy.decode(Response.self, from: data)
        } catch {
            throw FeddyError.decoding(String(describing: error))
        }
    }

    /// POST that returns a decoded response body. Used by upvote /
    /// addComment where the caller wants the server's new state to
    /// update the UI (vote count, the persisted comment row, ...).
    @available(iOS 15.0, macOS 12.0, *)
    func postReturning<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        let data = try await postRaw(path: path, body: body)
        do {
            return try JSONDecoder.feddy.decode(Response.self, from: data)
        } catch {
            throw FeddyError.decoding(String(describing: error))
        }
    }

    /// Apply Authorization + the cross-SDK X-Feddy-* headers shared by
    /// every outbound request. Centralising here means a new endpoint
    /// (or method) can never silently miss the SDK census headers.
    private func applyStandardHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(SDKVersion.userAgent, forHTTPHeaderField: "User-Agent")
        // SDK / host metadata census — server upserts workspace_sdk_usage
        // from these headers (see feddy-api/src/shared/sdk-usage.ts). Never
        // skipped: missing optional fields are simply omitted, server
        // tolerates that.
        request.setValue(SDKVersion.platform, forHTTPHeaderField: "X-Feddy-Sdk-Platform")
        request.setValue(SDKVersion.current, forHTTPHeaderField: "X-Feddy-Sdk-Version")
        if let appId = SDKVersion.appId {
            request.setValue(appId, forHTTPHeaderField: "X-Feddy-App-Id")
        }
        if let appVersion = SDKVersion.appVersion {
            request.setValue(appVersion, forHTTPHeaderField: "X-Feddy-App-Version")
        }
        if let appBuild = SDKVersion.appBuild {
            request.setValue(appBuild, forHTTPHeaderField: "X-Feddy-App-Build")
        }
        request.setValue(SDKVersion.osName, forHTTPHeaderField: "X-Feddy-Os-Name")
        request.setValue(SDKVersion.osVersion, forHTTPHeaderField: "X-Feddy-Os-Version")
        request.setValue(SDKVersion.deviceModel, forHTTPHeaderField: "X-Feddy-Device-Model")
        request.setValue(SDKVersion.deviceManufacturer, forHTTPHeaderField: "X-Feddy-Device-Manufacturer")
        request.setValue(SDKVersion.locale, forHTTPHeaderField: "X-Feddy-Locale")
    }

    @available(iOS 15.0, macOS 12.0, *)
    private func execute(_ request: URLRequest) async throws -> Data {
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
            let envelope = try? JSONDecoder.feddy.decode(APIErrorEnvelope.self, from: data)
            throw FeddyError.http(
                status: http.statusCode,
                code: envelope?.code,
                message: envelope?.message
            )
        }

        return data
    }
}

/// Server-side `apiError` shape: `{ code, message, details? }`.
private struct APIErrorEnvelope: Decodable {
    let code: String?
    let message: String?
}

extension JSONEncoder {
    static let feddy: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let feddy: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
