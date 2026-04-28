import XCTest
@testable import Feddy

final class FeddyConfigurationTests: XCTestCase {
    func test_acceptsPublishableKey() {
        XCTAssertNoThrow(try FeddyConfiguration(apiKey: "fed_pk_abc123"))
    }

    func test_rejectsKeyWithWrongPrefix() {
        XCTAssertThrowsError(try FeddyConfiguration(apiKey: "pk_live_oops")) { error in
            guard case FeddyError.invalidAPIKey = error else {
                return XCTFail("expected invalidAPIKey, got \(error)")
            }
        }
    }

    func test_rejectsSecretKey() {
        XCTAssertThrowsError(try FeddyConfiguration(apiKey: "fed_sk_abc123")) { error in
            guard
                case FeddyError.invalidAPIKey(let reason) = error,
                reason.lowercased().contains("secret")
            else {
                return XCTFail("expected invalidAPIKey mentioning 'secret', got \(error)")
            }
        }
    }

    func test_rejectsEmptyKey() {
        XCTAssertThrowsError(try FeddyConfiguration(apiKey: "   ")) { error in
            guard case FeddyError.invalidAPIKey = error else {
                return XCTFail("expected invalidAPIKey, got \(error)")
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
final class FeddyIdentifyTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func test_identify_sendsExpectedRequest() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session)

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{}".utf8))
        }

        try await client.identify(
            externalUserId: "user_42",
            email: "alice@example.com",
            displayName: "Alice",
            avatarURL: nil,
            profile: ["plan": .string("pro"), "seats": .int(3)]
        )

        let requests = MockURLProtocol.capturedRequests
        XCTAssertEqual(requests.count, 1)
        let req = try XCTUnwrap(requests.first)

        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/v1/identify")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer fed_pk_abc123")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(
            (req.value(forHTTPHeaderField: "User-Agent") ?? "").hasPrefix("Feddy-iOS/")
        )

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["external_user_id"] as? String, "user_42")
        XCTAssertEqual(json["email"] as? String, "alice@example.com")
        XCTAssertEqual(json["display_name"] as? String, "Alice")
        XCTAssertNil(json["anonymous_token"], "must not include anon token when external id is present")
        let profile = try XCTUnwrap(json["profile"] as? [String: Any])
        XCTAssertEqual(profile["plan"] as? String, "pro")
        XCTAssertEqual(profile["seats"] as? Int, 3)
    }

    func test_identify_fallsBackToAnonymousToken() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session, anonymousToken: "anon-fixed")

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        try await client.identify(
            externalUserId: nil,
            email: nil,
            displayName: nil,
            avatarURL: nil,
            profile: nil
        )

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        )
        XCTAssertNil(json["external_user_id"])
        XCTAssertEqual(json["anonymous_token"] as? String, "anon-fixed")
    }

    func test_identify_parsesServerErrorEnvelope() async {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session)

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data(#"{"code":"unauthorized","message":"Missing API key context"}"#.utf8)
            return (response, body)
        }

        do {
            try await client.identify(
                externalUserId: "user_42",
                email: nil, displayName: nil, avatarURL: nil, profile: nil
            )
            XCTFail("expected error")
        } catch let FeddyError.http(status, code, message) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(code, "unauthorized")
            XCTAssertEqual(message, "Missing API key context")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - helpers

    private func makeClient(
        session: URLSession,
        apiKey: String = "fed_pk_abc123",
        anonymousToken: String = "anon-test"
    ) -> FeddyClient {
        let config = try! FeddyConfiguration(
            apiKey: apiKey,
            baseURL: URL(string: "https://api.test.feddy.app")!
        )
        let suite = UserDefaults(suiteName: "feddy.tests.\(UUID().uuidString)")!
        let store = AnonymousTokenStore(
            defaults: suite,
            generator: { anonymousToken }
        )
        return FeddyClient(
            configuration: config,
            session: session,
            anonymousTokens: store
        )
    }
}

final class FeddyNotConfiguredTests: XCTestCase {
    func test_currentClient_withoutConfigure_throws() {
        Feddy.reset()
        XCTAssertThrowsError(try Feddy.currentClient()) { error in
            guard case FeddyError.notConfigured = error else {
                return XCTFail("expected notConfigured, got \(error)")
            }
        }
    }

    func test_publicIdentify_withoutConfigure_doesNotCrash() {
        Feddy.reset()
        // Public Feddy.identify is fire-and-forget; calling it without
        // configure should log + return cleanly, no throw, no crash.
        Feddy.identify(userId: "anyone")
    }
}
