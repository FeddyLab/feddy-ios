import XCTest
@testable import Feddy

@available(iOS 15.0, macOS 12.0, *)
final class FetchRequestsTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - fetchRequests (list)

    func test_fetchRequests_buildsExpectedURL() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session)

        MockURLProtocol.setHandler { request in
            let body = """
            {
              "items": [],
              "next_cursor": null
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        _ = try await client.fetchRequests(
            boardKey: "features",
            limit: 10,
            cursor: "abc"
        )

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(req.httpMethod, "GET")
        let components = try XCTUnwrap(
            URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(components.path, "/v1/requests")
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )
        XCTAssertEqual(query["board_key"], "features")
        XCTAssertEqual(query["limit"], "10")
        XCTAssertEqual(query["cursor"], "abc")
    }

    func test_fetchRequests_omitsNilQueryParams() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session)

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("""
            {"items": [], "next_cursor": null}
            """.utf8))
        }

        _ = try await client.fetchRequests(boardKey: nil, limit: 20, cursor: nil)

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let components = try XCTUnwrap(
            URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        )
        let names = (components.queryItems ?? []).map(\.name)
        // Limit always serialised; the other two stay absent rather
        // than getting sent as empty strings.
        XCTAssertTrue(names.contains("limit"))
        XCTAssertFalse(names.contains("board_key"))
        XCTAssertFalse(names.contains("cursor"))
    }

    func test_fetchRequests_decodesItemsAndCursor() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session)

        MockURLProtocol.setHandler { request in
            let body = """
            {
              "items": [
                {
                  "id": "r_1",
                  "title": "Dark mode",
                  "description": "Pretty please",
                  "request_type": "feature",
                  "status": "planned",
                  "priority": "high",
                  "board_id": "b_1",
                  "vote_count": 12,
                  "created_at": "2026-04-30T10:00:00.000Z"
                }
              ],
              "next_cursor": "MTAwOjEy"
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let page = try await client.fetchRequests(
            boardKey: nil,
            limit: 20,
            cursor: nil
        )

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.id, "r_1")
        XCTAssertEqual(page.items.first?.title, "Dark mode")
        XCTAssertEqual(page.items.first?.voteCount, 12)
        XCTAssertEqual(page.nextCursor, "MTAwOjEy")
    }

    // MARK: - fetchRequest (detail)

    func test_fetchRequest_decodesAttachments() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session)

        MockURLProtocol.setHandler { request in
            let body = """
            {
              "id": "r_42",
              "title": "Add export",
              "description": "Please add CSV",
              "request_type": "feature",
              "status": "planned",
              "priority": "medium",
              "board_id": "b_1",
              "official_reply": "We'll do it next sprint.",
              "vote_count": 7,
              "created_at": "2026-04-30T10:00:00.000Z",
              "attachments": [
                {
                  "key": "img/abc",
                  "asset_url": "https://cdn.feddy.app/img/abc",
                  "content_type": "image/png",
                  "size": 12345
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let detail = try await client.fetchRequest(id: "r_42")

        XCTAssertEqual(detail.id, "r_42")
        XCTAssertEqual(detail.officialReply, "We'll do it next sprint.")
        XCTAssertEqual(detail.attachments.count, 1)
        XCTAssertEqual(detail.attachments.first?.key, "img/abc")
        XCTAssertEqual(
            detail.attachments.first?.assetURL,
            URL(string: "https://cdn.feddy.app/img/abc")
        )
        XCTAssertEqual(detail.attachments.first?.contentType, "image/png")
        XCTAssertEqual(detail.attachments.first?.size, 12345)
    }

    func test_fetchRequest_emptyId_throws() async {
        let client = makeClient(session: MockURLProtocol.makeSession())
        do {
            _ = try await client.fetchRequest(id: " ")
            XCTFail("expected throw")
        } catch FeddyError.invalidPayload {
            // expected
        } catch {
            XCTFail("expected invalidPayload, got \(error)")
        }
    }

    func test_fetchRequest_passesThroughServerErrorEnvelope() async {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session)

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("""
            {"code":"request_not_found","message":"Request not found"}
            """.utf8))
        }

        do {
            _ = try await client.fetchRequest(id: "r_missing")
            XCTFail("expected throw")
        } catch FeddyError.http(let status, let code, _) {
            XCTAssertEqual(status, 404)
            XCTAssertEqual(code, "request_not_found")
        } catch {
            XCTFail("expected FeddyError.http, got \(error)")
        }
    }

    // MARK: - fetchComments

    func test_fetchComments_buildsExpectedURL() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session)

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("""
            {"items": [], "next_cursor": null}
            """.utf8))
        }

        _ = try await client.fetchComments(requestId: "r_1", limit: 50, cursor: nil)

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(req.url?.path, "/v1/requests/r_1/comments")
        XCTAssertEqual(req.httpMethod, "GET")
    }

    // MARK: - upvote

    func test_upvote_sendsAnonymousTokenWhenNoUser() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(
            session: session,
            externalUserId: nil,
            anonymousToken: "anon-fixed"
        )

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("""
            {"voted": true, "vote_count": 5}
            """.utf8))
        }

        let state = try await client.toggleVote(requestId: "r_99")

        XCTAssertTrue(state.voted)
        XCTAssertEqual(state.voteCount, 5)

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(req.url?.path, "/v1/requests/r_99/vote")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        )
        XCTAssertEqual(json["anonymous_token"] as? String, "anon-fixed")
        XCTAssertNil(json["external_user_id"])
    }

    func test_upvote_sendsExternalUserIdWhenIdentified() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(
            session: session,
            externalUserId: "user_42"
        )

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("""
            {"voted": false, "vote_count": 4}
            """.utf8))
        }

        _ = try await client.toggleVote(requestId: "r_99")

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        )
        XCTAssertEqual(json["external_user_id"] as? String, "user_42")
        XCTAssertNil(json["anonymous_token"])
    }

    // MARK: - addComment

    func test_addComment_trimsBodyAndDecodesResponse() async throws {
        let session = MockURLProtocol.makeSession()
        let client = makeClient(session: session, externalUserId: "user_42")

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("""
            {
              "id": "c_1",
              "request_id": "r_1",
              "author_end_user_id": "eu_42",
              "content": "hello",
              "created_at": "2026-04-30T10:00:00.000Z"
            }
            """.utf8))
        }

        let comment = try await client.addComment(requestId: "r_1", body: "  hello  ")

        XCTAssertEqual(comment.id, "c_1")
        XCTAssertEqual(comment.content, "hello")
        XCTAssertEqual(comment.authorEndUserId, "eu_42")
        XCTAssertEqual(comment.updatedAt, comment.createdAt)

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        )
        XCTAssertEqual(json["content"] as? String, "hello")
    }

    func test_addComment_emptyBodyThrows() async {
        let client = makeClient(session: MockURLProtocol.makeSession())
        do {
            _ = try await client.addComment(requestId: "r_1", body: "   ")
            XCTFail("expected throw")
        } catch FeddyError.invalidPayload {
            // expected
        } catch {
            XCTFail("expected invalidPayload, got \(error)")
        }
    }

    // MARK: - Helper

    private func makeClient(
        session: URLSession,
        externalUserId: String? = nil,
        anonymousToken: String = "anon-test"
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
            requestQueue: RequestQueue(defaults: suite)
        )
    }
}
