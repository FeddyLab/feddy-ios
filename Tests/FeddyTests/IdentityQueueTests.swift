import XCTest
@testable import Feddy

final class IdentityQueueTests: XCTestCase {
    /// Records every attempt; fails the first `failures` attempts with `error`.
    private actor Server {
        private(set) var attempts: [String] = []
        private(set) var delivered: [String] = []
        private var failures: Int
        private let error: Error

        init(failures: Int = 0, error: Error = URLError(.notConnectedToInternet)) {
            self.failures = failures
            self.error = error
        }

        func receive(_ payload: IdentityPayload) async throws {
            attempts.append(payload.externalId)
            // Give later submits a chance to arrive while this one is in flight.
            try await Task.sleep(nanoseconds: 1_000_000)
            if failures > 0 {
                failures -= 1
                throw error
            }
            delivered.append(payload.externalId)
        }
    }

    private func makeQueue(_ server: Server) -> IdentityQueue {
        IdentityQueue { try await server.receive($0) }
    }

    private func waitUntilIdle(_ queue: IdentityQueue) async {
        for _ in 0..<1_000 {
            if !queue.isSending { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("queue never went idle")
    }

    func testCallsMadeBackToBackLandInOrderAndLastWins() async {
        let server = Server()
        let queue = makeQueue(server)
        for i in 0..<20 { queue.submit(IdentityPayload(externalId: "\(i)")) }
        await waitUntilIdle(queue)

        let delivered = await server.delivered.compactMap(Int.init)
        XCTAssertEqual(delivered.last, 19)
        XCTAssertEqual(delivered, delivered.sorted(), "an older call landed after a newer one")
        XCTAssertLessThan(delivered.count, 20, "calls made while one was in flight should collapse")
    }

    func testTransientFailureIsResentOnFlush() async {
        let server = Server(failures: 1)
        let queue = makeQueue(server)
        queue.submit(IdentityPayload(externalId: "pro"))
        await waitUntilIdle(queue)
        let deliveredBeforeFlush = await server.delivered
        XCTAssertEqual(deliveredBeforeFlush, [])

        queue.flush()
        await waitUntilIdle(queue)
        let attempts = await server.attempts
        let delivered = await server.delivered
        XCTAssertEqual(attempts, ["pro", "pro"])
        XCTAssertEqual(delivered, ["pro"])
    }

    func testNewerCallReplacesAFailedOne() async {
        let server = Server(failures: 1)
        let queue = makeQueue(server)
        queue.submit(IdentityPayload(externalId: "old"))
        await waitUntilIdle(queue)

        queue.submit(IdentityPayload(externalId: "new"))
        await waitUntilIdle(queue)
        queue.flush()
        await waitUntilIdle(queue)
        let delivered = await server.delivered
        XCTAssertEqual(delivered, ["new"])
    }

    func testClientErrorIsNotRetried() async {
        let server = Server(failures: 1, error: APIError(status: 400, message: "bad external_id"))
        let queue = makeQueue(server)
        queue.submit(IdentityPayload(externalId: "bad"))
        await waitUntilIdle(queue)
        queue.flush()
        await waitUntilIdle(queue)
        let attempts = await server.attempts
        XCTAssertEqual(attempts, ["bad"])
    }

    func testRetryableErrors() {
        XCTAssertTrue(IdentityQueue.isRetryable(URLError(.timedOut)))
        XCTAssertTrue(IdentityQueue.isRetryable(APIError(status: 429, message: "")))
        XCTAssertTrue(IdentityQueue.isRetryable(APIError(status: 503, message: "")))
        XCTAssertFalse(IdentityQueue.isRetryable(APIError(status: 400, message: "")))
        XCTAssertFalse(IdentityQueue.isRetryable(APIError(status: 0, message: "invalid URL")))
    }
}
