import Foundation

/// Performs HTTP requests against `feddy-api`. One instance per `configure`
/// call; held via `Feddy`'s lock-guarded state.
actor FeddyClient {
    let configuration: FeddyConfiguration
    let session: URLSession
    let anonymousTokens: AnonymousTokenStore

    init(
        configuration: FeddyConfiguration,
        session: URLSession = .shared,
        anonymousTokens: AnonymousTokenStore = AnonymousTokenStore()
    ) {
        self.configuration = configuration
        self.session = session
        self.anonymousTokens = anonymousTokens
    }

    nonisolated var anonymousToken: String {
        anonymousTokens.tokenOrCreate()
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
        let url = configuration.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(SDKVersion.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONEncoder.feddy.encode(body)
        } catch {
            throw FeddyError.invalidPayload(reason: String(describing: error))
        }

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
