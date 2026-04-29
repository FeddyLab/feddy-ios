import XCTest
@testable import Feddy

@available(iOS 15.0, macOS 12.0, *)
final class RequestQueueTests: XCTestCase {
    func test_enqueue_andSnapshot_roundTrip() {
        let queue = makeQueue()

        queue.enqueue(path: "/v1/requests", body: Data(#"{"title":"a"}"#.utf8))
        queue.enqueue(path: "/v1/requests", body: Data(#"{"title":"b"}"#.utf8))

        XCTAssertEqual(queue.count, 2)
        let snap = queue.snapshot
        XCTAssertEqual(snap[0].body, Data(#"{"title":"a"}"#.utf8))
        XCTAssertEqual(snap[1].body, Data(#"{"title":"b"}"#.utf8))
    }

    func test_remove_byId() {
        let queue = makeQueue()
        queue.enqueue(path: "/v1/requests", body: Data(#"{"title":"a"}"#.utf8))
        queue.enqueue(path: "/v1/requests", body: Data(#"{"title":"b"}"#.utf8))
        let firstId = queue.snapshot[0].id

        queue.remove(id: firstId)

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.snapshot[0].body, Data(#"{"title":"b"}"#.utf8))
    }

    func test_capacity_dropsOldestWhenFull() {
        let queue = makeQueue(capacity: 3)
        for i in 0..<5 {
            queue.enqueue(
                path: "/v1/requests",
                body: Data(#"{"i":\#(i)}"#.utf8)
            )
        }

        XCTAssertEqual(queue.count, 3, "capacity cap must hold")
        let snap = queue.snapshot
        XCTAssertEqual(snap[0].body, Data(#"{"i":2}"#.utf8))
        XCTAssertEqual(snap[1].body, Data(#"{"i":3}"#.utf8))
        XCTAssertEqual(snap[2].body, Data(#"{"i":4}"#.utf8))
    }

    func test_replace_persistsInPlace() {
        let queue = makeQueue()
        queue.enqueue(path: "/v1/requests", body: Data("{}".utf8))

        var items = queue.snapshot
        items[0].attempts = 7
        queue.replace(items)

        XCTAssertEqual(queue.snapshot[0].attempts, 7)
    }

    func test_clear_emptiesQueue() {
        let queue = makeQueue()
        queue.enqueue(path: "/v1/requests", body: Data("{}".utf8))
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
    }

    func test_replay_dropsItemOnSuccess() async {
        let session = MockURLProtocol.makeSession()
        let queue = makeQueue()
        queue.enqueue(path: "/v1/requests", body: Data(#"{"title":"x"}"#.utf8))
        let client = makeClient(session: session, requestQueue: queue)

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        await client.replayQueue()

        XCTAssertTrue(queue.isEmpty, "successful replay must drop the item")
    }

    func test_replay_keepsItemOn5xx() async {
        let session = MockURLProtocol.makeSession()
        let queue = makeQueue()
        queue.enqueue(path: "/v1/requests", body: Data(#"{"title":"x"}"#.utf8))
        let client = makeClient(session: session, requestQueue: queue)

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        await client.replayQueue()

        XCTAssertEqual(queue.count, 1, "5xx must keep the item enqueued")
        XCTAssertEqual(queue.snapshot[0].attempts, 1, "attempt counter bumps")
    }

    func test_replay_dropsItemOn4xx() async {
        let session = MockURLProtocol.makeSession()
        let queue = makeQueue()
        queue.enqueue(path: "/v1/requests", body: Data(#"{"title":"x"}"#.utf8))
        let client = makeClient(session: session, requestQueue: queue)

        MockURLProtocol.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"code":"invalid_payload"}"#.utf8))
        }

        await client.replayQueue()

        XCTAssertTrue(queue.isEmpty, "4xx must drop — retrying bad data is a death loop")
    }

    // MARK: - helpers

    private func makeQueue(capacity: Int = RequestQueue.defaultCapacity) -> RequestQueue {
        let suite = UserDefaults(suiteName: "feddy.tests.\(UUID().uuidString)")!
        return RequestQueue(defaults: suite, capacity: capacity)
    }

    private func makeClient(
        session: URLSession,
        requestQueue: RequestQueue
    ) -> FeddyClient {
        let config = try! FeddyConfiguration(
            apiKey: "fed_abc123ABC012",
            baseURL: URL(string: "https://api.test.feddy.app")!
        )
        let suite = UserDefaults(suiteName: "feddy.tests.\(UUID().uuidString)")!
        return FeddyClient(
            configuration: config,
            session: session,
            identityStore: IdentityStore(defaults: suite, generator: { "anon" }),
            requestQueue: requestQueue
        )
    }
}
