import XCTest
@testable import Feddy

@available(iOS 15.0, macOS 12.0, *)
final class SubmitRequestTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func test_submitRequest_sendsExpectedRequest() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(
            session: session,
            externalUserId: "user_42"
        )

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"id":"r_1","status":"pending"}"#.utf8))
        }

        try await client.submitRequest(
            title: "Add dark mode",
            description: "Please support OLED dark theme",
            type: Feddy.RequestType.feature
        )

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/v1/requests")
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "Authorization"),
            "Bearer fed_abc123ABC012"
        )

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        )
        XCTAssertEqual(json["external_user_id"] as? String, "user_42")
        XCTAssertNil(json["anonymous_token"])
        XCTAssertEqual(json["title"] as? String, "Add dark mode")
        XCTAssertEqual(
            json["description"] as? String,
            "Please support OLED dark theme"
        )
        XCTAssertEqual(json["request_type"] as? String, "feature")
    }

    func test_submitRequest_fallsBackToAnonymousToken() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(
            session: session,
            externalUserId: nil,
            anonymousToken: "anon-fixed"
        )

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        try await client.submitRequest(
            title: "Crash on launch",
            description: nil,
            type: Feddy.RequestType.bug
        )

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        )
        XCTAssertNil(json["external_user_id"])
        XCTAssertEqual(json["anonymous_token"] as? String, "anon-fixed")
        XCTAssertEqual(json["request_type"] as? String, "bug")
    }

    func test_submitRequest_omitsTypeWhenNil() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(
            session: session,
            externalUserId: "user_42"
        )

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        try await client.submitRequest(
            title: "No type",
            description: nil,
            type: nil
        )

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        )
        XCTAssertNil(json["request_type"])
    }

    func test_submitRequest_5xx_enqueuesForRetry() async {
        let session = MockURLProtocol.makeSession()
        let queue = makeQueue()
        let client = makeClient(
            session: session,
            externalUserId: "user_42",
            requestQueue: queue
        )

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"code":"unavailable"}"#.utf8))
        }

        await client.submitRequestFireAndForget(
            title: "Server hiccup",
            description: nil,
            type: nil
        )

        XCTAssertEqual(queue.count, 1, "5xx must enqueue for retry")
    }

    func test_submitRequest_4xx_doesNotEnqueue() async {
        let session = MockURLProtocol.makeSession()
        let queue = makeQueue()
        let client = makeClient(
            session: session,
            externalUserId: "user_42",
            requestQueue: queue
        )

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"code":"invalid_payload"}"#.utf8))
        }

        await client.submitRequestFireAndForget(
            title: "Bad payload",
            description: nil,
            type: nil
        )

        XCTAssertTrue(queue.isEmpty, "4xx must not enqueue (would loop forever)")
    }

    func test_submitRequest_networkFailure_enqueuesForRetry() async {
        let session = MockURLProtocol.makeSession()
        let queue = makeQueue()
        let client = makeClient(
            session: session,
            externalUserId: "user_42",
            requestQueue: queue
        )

        MockURLProtocol.setHandler { _ in
            throw URLError(.notConnectedToInternet)
        }

        await client.submitRequestFireAndForget(
            title: "Offline submit",
            description: nil,
            type: nil
        )

        XCTAssertEqual(queue.count, 1, "URLError must enqueue for retry")
        let item = queue.snapshot.first!
        XCTAssertEqual(item.path, "/v1/requests")
        let json = try? JSONSerialization.jsonObject(with: item.body) as? [String: Any]
        XCTAssertEqual(json?["title"] as? String, "Offline submit")
    }

    func test_publicAPI_withoutConfigure_doesNotCrash() {
        Feddy.reset()
        Feddy.submitRequest(title: "Anything", description: nil, type: nil)
    }

    // MARK: - helpers

    private func makeQueue() -> RequestQueue {
        let suite = UserDefaults(suiteName: "feddy.tests.\(UUID().uuidString)")!
        return RequestQueue(defaults: suite)
    }

    private func makeClient(
        session: URLSession,
        externalUserId: String? = nil,
        anonymousToken: String = "anon-test",
        requestQueue: RequestQueue? = nil
    ) -> FeddyClient {
        let config = try! FeddyConfiguration(
            apiKey: "fed_abc123ABC012",
            baseURL: URL(string: "https://api.test.feddy.app")!
        )
        let suite = UserDefaults(suiteName: "feddy.tests.\(UUID().uuidString)")!
        let identityStore = IdentityStore(
            defaults: suite,
            generator: { anonymousToken }
        )
        identityStore.setLastExternalUserId(externalUserId)
        return FeddyClient(
            configuration: config,
            session: session,
            identityStore: identityStore,
            requestQueue: requestQueue ?? RequestQueue(defaults: suite)
        )
    }
}
